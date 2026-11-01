# DevFlow – Terraform

Provisions on AWS (default VPC):

- EC2 Ubuntu 22.04 host (`t3.small`, 20 GB gp3, IMDSv2) with an Elastic IP
- Security group: SSH from `admin_cidr` only, Jenkins `8080`, app ports `3001-3004`
- IAM role + instance profile (CloudWatch agent, read/write to the artifacts bucket)
- S3 artifacts bucket (versioned, private)
- `../ansible/inventory.ini`, generated for the Ansible step

State lives in a separate S3 bucket created by `bootstrap/`.

## Prerequisites

- Terraform >= 1.10, AWS CLI v2
- `aws configure` with an IAM user that can manage EC2, IAM and S3
- SSH key at `~/.ssh/id_ed25519(.pub)` (or set `ssh_public_key_path`)

## 1. Bootstrap the state bucket (once)

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=devflow-tfstate-<your-unique-suffix>"
```

## 2. Provision the infrastructure

```bash
cd terraform
cp backend.hcl.example backend.hcl            # set the bucket name
cp terraform.tfvars.example terraform.tfvars  # set admin_cidr
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## Saving money

`t3.small` is not free-tier. Stop the instance when not in use (the Elastic IP keeps the address),
or tear everything down with `terraform destroy`.
