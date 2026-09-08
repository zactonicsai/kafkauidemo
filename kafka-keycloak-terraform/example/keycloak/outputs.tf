output "launch_template_id" {
  value = module.keycloak_launch_template.id
}

output "launch_template_latest_version" {
  value = module.keycloak_launch_template.latest_version
}

output "alb_dns_name" {
  description = "Internal ALB DNS name – create a private Route53 record for keycloak_hostname pointing here."
  value       = aws_lb.keycloak.dns_name
}

output "alb_zone_id" {
  value = aws_lb.keycloak.zone_id
}

output "alb_arn" {
  value = aws_lb.keycloak.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.keycloak.arn
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "instance_security_group_id" {
  value = aws_security_group.instance.id
}

output "instance_id" {
  value = try(module.keycloak_instance[0].id, null)
}

output "instance_private_ip" {
  value = try(module.keycloak_instance[0].private_ip, null)
}

output "keycloak_url" {
  value = "${local.scheme}://${var.keycloak_hostname}${local.listener_port == 443 || local.listener_port == 80 ? "" : ":${local.listener_port}"}"
}

output "effective_keycloak_env" {
  description = "Final KC_* map after merging defaults with keycloak_env (secrets are not included)."
  value       = local.keycloak_env
}
