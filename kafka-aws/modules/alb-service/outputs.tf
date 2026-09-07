output "target_group_arn" { value = aws_lb_target_group.this.arn }
output "url" { value = "https://${var.hostname}" }
