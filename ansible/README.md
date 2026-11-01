# DevFlow – Ansible

Configures the EC2 host that Terraform creates.

| Role | What it does |
|---|---|
| `common` | git, curl, jq etc., timezone, 2 GB swap |
| `docker` | Docker Engine from Docker's apt repo, log rotation, `ubuntu` user in `docker` group |
| `jenkins` | Java 17, Jenkins LTS, `jenkins` user in `docker` group, prints the initial admin password |
| `cloudwatch` | CloudWatch agent: CPU/memory/swap/disk metrics (namespace `DevFlow`), syslog and container logs (`/devflow/*` log groups) |
| `app_env` | `/opt/devflow/<env>.env` for development, testing, staging, production |

## Prerequisites

Ansible does not run natively on Windows; use WSL (Ubuntu):

```bash
sudo apt update && sudo apt install -y ansible
ansible-galaxy collection install -r requirements.yml
```

Copy your SSH key into WSL (`~/.ssh/id_ed25519`, mode `600`) – keys on `/mnt/c` have the wrong permissions.

## Run

`terraform apply` writes `inventory.ini` here. Then:

```bash
cd ansible
ansible devflow -i inventory.ini -m ping   # check SSH works
ansible-playbook -i inventory.ini site.yml
```

Running from `/mnt/c` or `/mnt/e`, Ansible ignores `ansible.cfg` (world-writable directory), which is why
`-i inventory.ini` is passed explicitly. Host-key prompts can be skipped with `export ANSIBLE_HOST_KEY_CHECKING=False`.

The last Jenkins task prints the URL and the initial admin password. Finish the setup wizard in the browser
(install suggested plugins + **GitHub** and **Docker Pipeline**).

The playbook is idempotent: re-running it only changes what drifted.
