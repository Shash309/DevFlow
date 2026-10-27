# DevFlow

Multi-environment CI/CD pipeline: Git branch → Jenkins → Docker → AWS EC2.

| Branch    | Environment | Port |
|-----------|-------------|------|
| develop   | development | 3001 |
| testing   | testing     | 3002 |
| staging   | staging     | 3003 |
| main      | production  | 3004 |

## Layout

- `app/` – sample Node.js (Express) app with `/` and `/health`
- `terraform/` – AWS infrastructure (EC2, SG, IAM, S3)
- `ansible/` – server configuration (Docker, Java, Jenkins, CloudWatch agent)
- `Jenkinsfile` – pipeline definition (Phase 4)
- `docs/` – diagrams and report

## Run the app locally

```bash
cd app
npm install
npm test
npm start          # http://localhost:3000
```

## Run with Docker

```bash
docker build -t devflow:local app
docker run -d -p 3001:3000 -e APP_ENV=development --name devflow-development devflow:local
curl http://localhost:3001/health
```
