output "kafka_instance_id" {
  value = try(module.kafka[0].id, null)
}

output "keycloak_instance_id" {
  value = try(module.keycloak[0].id, null)
}

output "kafka_public_ip" {
  value = try(module.kafka_eip[0].public_ip, null)
}

output "keycloak_public_ip" {
  value = local.keycloak_public_ip
}

output "keycloak_private_ip" {
  value = local.keycloak_private_ip
}

output "kafka_ui_url" {
  value = try("http://${module.kafka_eip[0].public_ip}:8080", null)
}

output "keycloak_url" {
  value = local.keycloak_public_ip == null ? null : "https://${local.keycloak_public_ip}:8443"
}

output "keycloak_admin_url" {
  value = local.keycloak_public_ip == null ? null : "https://${local.keycloak_public_ip}:8443/admin/"
}

output "keycloak_metrics_url" {
  value = local.keycloak_public_ip == null ? null : "https://${local.keycloak_public_ip}:9000/metrics"
}

output "keycloak_health_url" {
  value = local.keycloak_public_ip == null ? null : "https://${local.keycloak_public_ip}:9000/health/ready"
}

output "kafka_ui_username" {
  value = var.kafka.ui_username
}

output "kafka_ui_user_password" {
  value     = local.kafka_ui_password
  sensitive = true
}

output "keycloak_admin_username" {
  value = var.keycloak.admin_username
}

output "keycloak_admin_password" {
  value     = local.keycloak_admin_password
  sensitive = true
}

output "ssm_kafka" {
  value = try("aws ssm start-session --region ${var.aws_region} --target ${module.kafka[0].id}", null)
}

output "ssm_keycloak" {
  value = try("aws ssm start-session --region ${var.aws_region} --target ${module.keycloak[0].id}", null)
}

output "network_inputs_resolved" {
  description = "What this stack resolved from the network stack / overrides."
  value = {
    subnet_id                   = local.subnet_id
    keycloak_security_group_ids = local.keycloak_security_group_ids
    kafka_security_group_ids    = local.kafka_security_group_ids
    instance_profile_name       = local.instance_profile_name
    ami_id                      = local.ami_id
  }
}
