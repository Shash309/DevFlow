# DevFlow – 5-minute demo script

Total narration: about 720 words, roughly 5 minutes at a calm pace.
**[SCREEN]** = what to show. Normal text = what to say.

---

## 1. The problem (0:00 – 0:25)

**[SCREEN]** README, top section.

DevFlow is a CI/CD platform that takes code from a `git push` to production with no manual steps.
Manual deployment means build, test, copy, restart, all by hand. That's slow, error-prone, and every
environment slowly drifts apart. DevFlow replaces all of that with code: infrastructure, configuration,
the pipeline and the deployments.

## 2. How the pipeline came into existence (0:25 – 1:05)

**[SCREEN]** `terraform/` and `ansible/roles/`, then `scripts/setup.ps1`.

It started on AWS. **Terraform** provisions the infrastructure as code (EC2, IAM, S3 for state, and
CloudWatch alarms), so the whole server can be rebuilt with one command. **Ansible** then configures that
server: Docker, Jenkins and the CloudWatch agent, each as a reusable role. Running it twice gives the same
result, which is what idempotent means.

Then I moved the platform to **Kubernetes**, running locally on Docker Desktop. Now `setup.ps1` brings
up the whole lab in one command, and every step checks what already exists, so it's safe to re-run.

## 3. The platform layer (1:05 – 1:50)

**[SCREEN]** `k8s/namespaces.yaml`, `quotas.yaml`, `jenkins-rbac.yaml`; terminal: `kubectl get ns`.

Each environment (development, testing, staging, production) gets its own **namespace**, which is a
separate room inside the cluster. **Resource quotas** cap CPU and memory, so one environment can't
starve the others.

Jenkins deploys through a **ServiceAccount with RBAC**. It can manage only the app namespaces and
nothing else in the cluster. That's least privilege.

**[SCREEN]** `ci/docker-compose.yml`, `ci/jenkins/casc.yaml`.

Next to the cluster run three CI services: a **private Docker registry** that stores every image,
**SonarQube** for code quality, and **Jenkins**, which configures itself from YAML using
Configuration as Code. Nobody clicks through a setup wizard.

## 4. The pipeline, stage by stage (1:50 – 3:30)

**[SCREEN]** `Jenkinsfile`, then the Jenkins stage view of a running build.

The whole pipeline is a `Jenkinsfile`. Jenkins checks GitHub every minute, and the branch decides the
destination: develop goes to development, testing to testing, staging to staging, main to production.
Feature branches are built and tested but never deployed.

- **Lint**: ESLint catches style problems and obvious bugs in seconds.
- **Unit tests**: Jest checks each function in isolation.
- **Integration tests**: run against a real **PostgreSQL** container, so we test the actual database,
  not a mock.

**[SCREEN]** SonarQube dashboard.

- **SonarQube analysis**: measures bugs, code smells, duplication and test coverage.
- **Quality Gate**: Jenkins polls SonarQube for the verdict. If the code fails the gate, the build
  stops here and nothing gets deployed.

**[SCREEN]** Back to Jenkins.

- **Build image**: packages the app into a Docker image tagged with the build number.
- **Trivy scan**: scans that image for known vulnerabilities and blocks fixable critical ones.
- **Push**: sends the image to the private registry.
- **Approval**: production only. A human clicks *Deploy*, so nothing reaches production by accident.

## 5. Deployment, safety net and scaling (3:30 – 4:20)

**[SCREEN]** `charts/devflow/` (`values-*.yaml`), Jenkins *Deploy* and *Smoke Test* logs.

Deployment uses a **Helm chart**: one template, with one values file per environment. Production gets
more replicas and bigger limits from the same code. Helm runs with `--atomic`, so if the new pods never
become healthy, it rolls back automatically.

After deployment, a **smoke test** calls `/health` and checks that the app is up, the database is
connected, and the running build number matches. If any check fails, the pipeline runs
`helm rollback` and the previous version keeps serving users.

**[SCREEN]** `hpa.yaml`, `pdb.yaml`; browser at `localhost:30001` and `localhost:30004`.

In production, a **Horizontal Pod Autoscaler** adds pods under load, and a **PodDisruptionBudget**
keeps a minimum running during maintenance. Here's the same app live in development and in production.

## 6. Observability (4:20 – 4:45)

**[SCREEN]** Prometheus targets (`localhost:30090`), Grafana dashboard (`localhost:30300`).

**Prometheus** scrapes metrics from the cluster and the app. **Grafana** turns them into a dashboard
with CPU, memory, request rates and pod counts, so we can see whether a release is healthy, not just
whether it deployed. On AWS, CloudWatch played the same role, with email alarms.

## 7. Wrap-up (4:45 – 5:00)

**[SCREEN]** Jenkins with all branches green.

Each piece has a single job: Terraform and Ansible build the ground, Kubernetes isolates and scales,
Jenkins orchestrates, SonarQube and Trivy guard quality and security, Helm deploys safely, and
Prometheus with Grafana watches the result. Together they turn a `git push` into a tested,
scanned, monitored release. That's DevFlow.

---

### Before recording
- Let the first build finish on `develop`, `testing`, `staging` and `main`, so ports 30001–30004 respond.
- Keep one build of `main` paused at the approval step if you want to show it live.
- Open every tab in advance: VS Code, Jenkins, SonarQube, Grafana, Prometheus, the app ports.
- Record with **Win + Alt + R** (Xbox Game Bar) or OBS. Zoom VS Code to about 130 % so the code is readable.
