# Metrics for mem/disk/swap come from the CloudWatch agent installed by Ansible
# (namespace "DevFlow", aggregated by InstanceId). CPU/network/status come from EC2.

locals {
  agent_namespace = "DevFlow"
  instance_dims   = { InstanceId = aws_instance.devflow.id }
  alarm_actions   = [aws_sns_topic.alerts.arn]
}

# ---------- Alert delivery ----------

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# AWS sends a confirmation email; alerts only arrive after the link in it is clicked.
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------- Alarms ----------

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  alarm_description   = "CPU above ${var.cpu_alarm_threshold}% for 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = local.instance_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.project_name}-memory-high"
  alarm_description   = "Memory above ${var.memory_alarm_threshold}% for 10 minutes"
  namespace           = local.agent_namespace
  metric_name         = "mem_used_percent"
  dimensions          = local.instance_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.memory_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name          = "${var.project_name}-disk-high"
  alarm_description   = "Root disk above ${var.disk_alarm_threshold}% used"
  namespace           = local.agent_namespace
  metric_name         = "disk_used_percent"
  dimensions          = local.instance_dims
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.disk_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.project_name}-status-check-failed"
  alarm_description   = "EC2 instance or system status check failing"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = local.instance_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# Counts lines that look like errors in the app containers' logs
resource "aws_cloudwatch_log_metric_filter" "container_errors" {
  name           = "${var.project_name}-container-errors"
  log_group_name = aws_cloudwatch_log_group.containers.name
  pattern        = "?Error ?ERROR ?error ?Exception"

  metric_transformation {
    name          = "ContainerErrors"
    namespace     = local.agent_namespace
    value         = "1"
    default_value = "0"
  }
}

# Created here (not by the agent) so the metric filter has a group to attach to
resource "aws_cloudwatch_log_group" "containers" {
  name              = "/devflow/containers"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/devflow/system"
  retention_in_days = 14
}

# ---------- Dashboard ----------

resource "aws_cloudwatch_dashboard" "devflow" {
  dashboard_name = var.project_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = join("", [
            "# DevFlow host ${aws_instance.devflow.id}\n",
            join(" · ", [for env, port in var.app_ports : "[${env}](http://${aws_eip.devflow.public_ip}:${port})"]),
            " · [Jenkins](http://${aws_eip.devflow.public_ip}:8080)",
          ])
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title   = "CPU utilisation (%)"
          region  = var.aws_region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.devflow.id]]
          yAxis   = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = var.cpu_alarm_threshold, label = "alarm" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Memory and swap used (%)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            [local.agent_namespace, "mem_used_percent", "InstanceId", aws_instance.devflow.id, { label = "memory" }],
            [local.agent_namespace, "swap_used_percent", "InstanceId", aws_instance.devflow.id, { label = "swap" }],
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = var.memory_alarm_threshold, label = "alarm" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title   = "Root disk used (%)"
          region  = var.aws_region
          view    = "gauge"
          stat    = "Maximum"
          period  = 300
          metrics = [[local.agent_namespace, "disk_used_percent", "InstanceId", aws_instance.devflow.id]]
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Network (bytes)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.devflow.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.devflow.id],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Container error log lines"
          region  = var.aws_region
          view    = "bar"
          stat    = "Sum"
          period  = 300
          metrics = [[local.agent_namespace, "ContainerErrors"]]
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 14
        width  = 24
        height = 3
        properties = {
          title = "Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.cpu_high.arn,
            aws_cloudwatch_metric_alarm.memory_high.arn,
            aws_cloudwatch_metric_alarm.disk_high.arn,
            aws_cloudwatch_metric_alarm.status_check.arn,
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 17
        width  = 24
        height = 8
        properties = {
          title  = "Latest container logs"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.containers.name}' | fields @timestamp, @logStream, @message | sort @timestamp desc | limit 50"
        }
      },
    ]
  })
}
