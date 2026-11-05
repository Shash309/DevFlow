// DevFlow CI/CD pipeline
//
//   CI (every branch):  lint -> unit tests -> integration tests (real PostgreSQL)
//                       -> SonarQube analysis -> Quality Gate -> Docker build -> Trivy scan
//   CD (env branches):  push to registry -> [approval for production] -> Helm deploy to the
//                       branch's Kubernetes namespace -> smoke test -> automatic rollback on failure
//
//   develop -> development (:30001)   testing -> testing (:30002)
//   staging -> staging     (:30003)   main    -> production (:30004)
//   feature/* -> CI only, no deployment

def ENVIRONMENTS = [
    develop: [name: 'development', port: '30001'],
    testing: [name: 'testing',     port: '30002'],
    staging: [name: 'staging',     port: '30003'],
    main:    [name: 'production',  port: '30004'],
]

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '15'))
        timeout(time: 40, unit: 'MINUTES')
    }

    environment {
        REGISTRY   = 'localhost:5000'
        IMAGE_NAME = 'devflow'
        CHART      = 'charts/devflow'
        // Containers started by the pipeline join the CI network, so Jenkins reaches them by name
        CI_NETWORK = 'devflow-ci'
        // Kubernetes NodePorts are published on the Docker host
        K8S_HOST   = 'host.docker.internal'
    }

    stages {
        stage('Resolve Environment') {
            steps {
                script {
                    def target = ENVIRONMENTS[env.BRANCH_NAME]
                    env.DEPLOY_ENV = target ? target.name : ''
                    env.NODE_PORT  = target ? target.port : ''
                    env.IMAGE_TAG  = "${target ? target.name : 'ci'}-${env.BUILD_NUMBER}"
                    env.IMAGE      = "${env.REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.BRANCH_NAME} -> ${target ? target.name : 'CI only'}"
                    echo "Branch ${env.BRANCH_NAME}: ${target ? "deploys to namespace ${target.name}" : 'CI only, no deployment'}"
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                dir('app') {
                    sh 'node --version && npm ci --no-audit --no-fund'
                }
            }
        }

        stage('Lint') {
            steps {
                dir('app') {
                    sh 'npm run lint -- --max-warnings 0'
                }
            }
        }

        stage('Unit Tests') {
            steps {
                dir('app') {
                    sh 'npm run test:unit'
                }
            }
            post {
                always { junit allowEmptyResults: true, testResults: 'app/reports/junit.xml' }
            }
        }

        stage('Integration Tests') {
            steps {
                script {
                    // Throwaway PostgreSQL just for this build
                    def db = "devflow-it-${env.BUILD_TAG}".replaceAll('[^a-zA-Z0-9_.-]', '-').toLowerCase()
                    try {
                        sh """
                            docker run -d --name ${db} --network ${CI_NETWORK} \
                              -e POSTGRES_USER=devflow -e POSTGRES_PASSWORD=devflow -e POSTGRES_DB=devflow \
                              postgres:16-alpine
                            for i in \$(seq 1 30); do
                              docker exec ${db} pg_isready -U devflow -d devflow && break
                              sleep 2
                            done
                        """
                        dir('app') {
                            // All tests, with coverage for SonarQube
                            sh "DATABASE_URL=postgres://devflow:devflow@${db}:5432/devflow npm run test:coverage"
                        }
                    } finally {
                        sh "docker rm -f ${db} || true"
                    }
                }
            }
            post {
                always { junit allowEmptyResults: true, testResults: 'app/reports/junit.xml' }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonarqube') {
                    // The scanner runs as a container that shares Jenkins' workspace volume
                    sh '''
                        docker run --rm -u 0 --network "$CI_NETWORK" \
                          --volumes-from devflow-jenkins -w "$WORKSPACE" \
                          -e SONAR_HOST_URL -e SONAR_TOKEN="$SONAR_AUTH_TOKEN" \
                          sonarsource/sonar-scanner-cli:latest \
                          -Dsonar.projectVersion="$BUILD_NUMBER"
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    // SonarQube calls back Jenkins' webhook; the build fails if the gate fails
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build Image') {
            steps {
                sh 'docker build --pull --build-arg BUILD_NUMBER="$BUILD_NUMBER" -t "$IMAGE" app'
            }
        }

        stage('Security Scan (Trivy)') {
            steps {
                // Report HIGH and CRITICAL, fail the build only on fixable CRITICAL vulnerabilities
                sh '''
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                      -v devflow-trivy-cache:/root/.cache aquasec/trivy:0.58.1 \
                      image --no-progress --severity HIGH,CRITICAL --ignore-unfixed --exit-code 0 "$IMAGE"
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                      -v devflow-trivy-cache:/root/.cache aquasec/trivy:0.58.1 \
                      image --no-progress --skip-db-update --severity CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE"
                '''
            }
        }

        stage('Push Image') {
            when { expression { env.DEPLOY_ENV } }
            steps {
                sh 'docker push "$IMAGE"'
            }
        }

        stage('Approve Production') {
            when { branch 'main' }
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    input message: "Deploy build #${env.BUILD_NUMBER} to PRODUCTION?", ok: 'Deploy'
                }
            }
        }

        stage('Deploy (Helm)') {
            when { expression { env.DEPLOY_ENV } }
            steps {
                // --atomic: if the new pods never become ready, Helm rolls back automatically
                sh '''
                    helm upgrade --install devflow "$CHART" \
                      --namespace "$DEPLOY_ENV" \
                      -f "$CHART/values-$DEPLOY_ENV.yaml" \
                      --set image.tag="$IMAGE_TAG" \
                      --set buildNumber="$BUILD_NUMBER" \
                      --atomic --wait --timeout 5m
                    kubectl -n "$DEPLOY_ENV" get deploy,statefulset,pods,svc
                    helm history devflow -n "$DEPLOY_ENV" --max 5
                '''
            }
        }

        stage('Smoke Test') {
            when { expression { env.DEPLOY_ENV } }
            steps {
                script {
                    try {
                        retry(10) {
                            sleep 3
                            sh '''
                                curl -fsS "http://$K8S_HOST:$NODE_PORT/health" | tee health.json
                                jq -e --arg b "$BUILD_NUMBER" '.status == "UP" and .database == "UP" and .build == $b' health.json
                                curl -fsS "http://$K8S_HOST:$NODE_PORT/api/tasks" > /dev/null
                            '''
                        }
                    } catch (err) {
                        echo 'Smoke test failed: rolling back to the previous release'
                        sh 'helm rollback devflow -n "$DEPLOY_ENV" --wait || true'
                        throw err
                    }
                }
            }
        }
    }

    post {
        success {
            script {
                if (env.DEPLOY_ENV) {
                    echo "Deployed ${env.IMAGE} to ${env.DEPLOY_ENV}: http://localhost:${env.NODE_PORT}"
                } else {
                    echo "CI passed for ${env.BRANCH_NAME} (no deployment for this branch)"
                }
            }
        }
        failure {
            echo "Build failed on ${env.BRANCH_NAME}. Nothing broken was deployed."
        }
        cleanup {
            // Keep the 3 newest local images per environment
            sh '''
                prefix="${DEPLOY_ENV:-ci}"
                docker images "$REGISTRY/$IMAGE_NAME" --format '{{.Tag}}' \
                  | grep "^$prefix-" | sort -t- -k2 -n -r | tail -n +4 \
                  | xargs -r -I{} docker rmi "$REGISTRY/$IMAGE_NAME:{}" || true
            '''
        }
    }
}
