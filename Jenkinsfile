// DevFlow multi-environment pipeline.
// The Git branch decides the target environment; any other branch is built and tested only.
//
// Requires on the Jenkins host (set up by ansible/): Docker, the jenkins user in the docker group,
// /opt/devflow/<env>.env files. Plugins: Pipeline, Git, GitHub, Docker Pipeline.

def ENVIRONMENTS = [
    'develop': [name: 'development', port: 3001],
    'testing': [name: 'testing',     port: 3002],
    'staging': [name: 'staging',     port: 3003],
    'main'   : [name: 'production',  port: 3004],
]

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 20, unit: 'MINUTES')
    }

    environment {
        IMAGE_NAME = 'devflow'
        APP_DIR    = 'app'
        ENV_DIR    = '/opt/devflow'
    }

    stages {
        stage('Resolve Environment') {
            steps {
                script {
                    def target = ENVIRONMENTS[env.BRANCH_NAME]
                    env.DEPLOY      = target ? 'true' : 'false'
                    env.APP_ENV     = target ? target.name : 'none'
                    env.HOST_PORT   = target ? "${target.port}" : ''
                    env.IMAGE_TAG   = "${env.APP_ENV}-${env.BUILD_NUMBER}"
                    env.CONTAINER   = "${env.IMAGE_NAME}-${env.APP_ENV}"
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.BRANCH_NAME} -> ${env.APP_ENV}"
                    echo "Branch '${env.BRANCH_NAME}' -> environment '${env.APP_ENV}' (deploy: ${env.DEPLOY})"
                }
            }
        }

        stage('Install & Test') {
            agent {
                docker {
                    image 'node:20-alpine'
                    reuseNode true
                }
            }
            environment {
                // npm needs a writable cache dir when running as the jenkins uid
                HOME = "${env.WORKSPACE}"
            }
            steps {
                dir(env.APP_DIR) {
                    sh 'npm ci'
                    sh 'npm test'
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'app/coverage/**', allowEmptyArchive: true
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh """
                    docker build \
                      --build-arg BUILD_NUMBER=${env.BUILD_NUMBER} \
                      -t ${env.IMAGE_NAME}:${env.IMAGE_TAG} \
                      ${env.APP_DIR}
                """
            }
        }

        stage('Deploy') {
            when { environment name: 'DEPLOY', value: 'true' }
            steps {
                script {
                    // Remember what is running now so a failed health check can roll back to it
                    env.PREVIOUS_IMAGE = sh(
                        script: "docker inspect --format '{{.Config.Image}}' ${env.CONTAINER} 2>/dev/null || true",
                        returnStdout: true
                    ).trim()
                    echo "Previous image: ${env.PREVIOUS_IMAGE ?: 'none'}"
                }
                sh """
                    docker rm -f ${env.CONTAINER} 2>/dev/null || true
                    docker run -d \
                      --name ${env.CONTAINER} \
                      --restart unless-stopped \
                      --env-file ${env.ENV_DIR}/${env.APP_ENV}.env \
                      -e BUILD_NUMBER=${env.BUILD_NUMBER} \
                      -p ${env.HOST_PORT}:3000 \
                      ${env.IMAGE_NAME}:${env.IMAGE_TAG}
                """
            }
        }

        stage('Health Check') {
            when { environment name: 'DEPLOY', value: 'true' }
            steps {
                retry(10) {
                    sleep(time: 3, unit: 'SECONDS')
                    sh "curl -fsS http://localhost:${env.HOST_PORT}/health"
                }
                echo "${env.APP_ENV} is healthy on port ${env.HOST_PORT}"
            }
            post {
                failure {
                    script {
                        if (env.PREVIOUS_IMAGE) {
                            echo "Health check failed - rolling back to ${env.PREVIOUS_IMAGE}"
                            sh """
                                docker rm -f ${env.CONTAINER} 2>/dev/null || true
                                docker run -d \
                                  --name ${env.CONTAINER} \
                                  --restart unless-stopped \
                                  --env-file ${env.ENV_DIR}/${env.APP_ENV}.env \
                                  -p ${env.HOST_PORT}:3000 \
                                  ${env.PREVIOUS_IMAGE}
                            """
                        } else {
                            echo 'Health check failed and there is no previous image to roll back to'
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Build #${env.BUILD_NUMBER} (${env.BRANCH_NAME}) succeeded" +
                 (env.DEPLOY == 'true' ? " - deployed to ${env.APP_ENV} on port ${env.HOST_PORT}" : ' - not a deploy branch')
        }
        failure {
            echo "Build #${env.BUILD_NUMBER} (${env.BRANCH_NAME}) failed - nothing new was deployed"
        }
        always {
            // Keep the 3 newest images per environment; older ones are only needed for manual rollback
            sh """
                docker images ${env.IMAGE_NAME} --format '{{.Tag}}' \
                  | grep '^${env.APP_ENV}-' | sort -t- -k2 -n -r | tail -n +4 \
                  | xargs -r -I{} docker rmi ${env.IMAGE_NAME}:{} || true
                docker image prune -f || true
            """
        }
    }
}
