variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "devflow"
}

variable "instance_type" {
  description = "t3.small (2 GB) is the minimum for Jenkins + 4 app containers"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root disk size in GB (Docker images and Jenkins workspaces live here)"
  type        = number
  default     = 20
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Only written into the generated Ansible inventory"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.7/32); SSH is only allowed from here"
  type        = string
}

variable "jenkins_cidrs" {
  description = "Who can reach Jenkins on 8080. Must include GitHub webhook IPs, so it is open by default."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_ports" {
  description = "Host port for each environment's container"
  type        = map(number)
  default = {
    development = 3001
    testing     = 3002
    staging     = 3003
    production  = 3004
  }
}
