output "public_ip" {
  value = aws_eip.devflow.public_ip
}

output "ssh_command" {
  value = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_eip.devflow.public_ip}"
}

output "jenkins_url" {
  value = "http://${aws_eip.devflow.public_ip}:8080"
}

output "github_webhook_url" {
  value = "http://${aws_eip.devflow.public_ip}:8080/github-webhook/"
}

output "app_urls" {
  value = { for env, port in var.app_ports : env => "http://${aws_eip.devflow.public_ip}:${port}" }
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "cloudwatch_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.devflow.dashboard_name}"
}
