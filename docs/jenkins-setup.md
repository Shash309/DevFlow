# Jenkins setup

Run this once after `ansible-playbook site.yml` has finished. The playbook prints the Jenkins URL and the
initial admin password.

## 1. Setup wizard

1. Open `http://<public-ip>:8080` and paste the initial admin password.
2. **Install suggested plugins**.
3. Create the admin user. Keep the Jenkins URL as `http://<public-ip>:8080/`.

## 2. Extra plugins

*Manage Jenkins → Plugins → Available*, install:

- **Docker Pipeline** – runs the test stage inside `node:20-alpine`
- **GitHub** – webhook trigger (usually already installed with the suggested plugins)

Restart Jenkins when asked.

## 3. Multibranch Pipeline job

1. *New Item* → name `DevFlow` → **Multibranch Pipeline**.
2. *Branch Sources → Add source → GitHub*
   - Repository URL: `https://github.com/Shash309/DevFlow.git`
   - Credentials: none needed while the repo is public. For a private repo, add a GitHub
     *Username with password* credential that uses a personal access token as the password.
3. *Build Configuration*: by Jenkinsfile, script path `Jenkinsfile`.
4. *Scan Multibranch Pipeline Triggers*: tick *Periodically if not otherwise run*, interval **5 minutes**
   (a fallback in case a webhook is missed).
5. Save. Jenkins scans the repo and creates one job per branch that has a `Jenkinsfile`.

## 4. GitHub webhook (instant builds on push)

GitHub repo → *Settings → Webhooks → Add webhook*:

| Field | Value |
|---|---|
| Payload URL | `http://<public-ip>:8080/github-webhook/` (from `terraform output github_webhook_url`) |
| Content type | `application/json` |
| Events | *Just the push event* |

GitHub sends a test ping; a green tick means Jenkins received it.

## How the pipeline behaves

| Branch | Environment | URL |
|---|---|---|
| `develop` | development | `http://<public-ip>:3001` |
| `testing` | testing | `http://<public-ip>:3002` |
| `staging` | staging | `http://<public-ip>:3003` |
| `main` | production | `http://<public-ip>:3004` |
| anything else | – | built and tested, not deployed |

Stages: Resolve Environment → Install & Test → Build Docker Image → Deploy → Health Check.

- A failing test or image build stops the pipeline before anything is deployed.
- If the new container fails `/health`, the previous image for that environment is started again and the
  build is marked failed.
- The 3 newest images per environment are kept for manual rollback:
  ```bash
  docker images devflow
  docker rm -f devflow-production
  docker run -d --name devflow-production --restart unless-stopped \
    --env-file /opt/devflow/production.env -p 3004:3000 devflow:production-<build>
  ```
