output "name_servers" {
  description = "Set these at your domain registrar (NS records for the domain)"
  value       = aws_route53_zone.main.name_servers
}

output "hosted_zone_id" {
  value = aws_route53_zone.main.zone_id
}

output "keycloak_url" {
  value = "https://${local.keycloak_host}"
}

output "kafka_ui_url" {
  value = "https://${local.kafka_ui_host}"
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "instance_id" {
  description = "Use: aws ssm start-session --target <id>"
  value       = aws_instance.app.id
}

output "target_group_arns" {
  value = {
    keycloak = aws_lb_target_group.keycloak.arn
    kafka_ui = aws_lb_target_group.kafka_ui.arn
  }
}
