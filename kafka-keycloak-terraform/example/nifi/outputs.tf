output "launch_template_id" {
  value = module.nifi_launch_template.id
}

output "launch_template_arn" {
  value = module.nifi_launch_template.arn
}

output "launch_template_latest_version" {
  value = module.nifi_launch_template.latest_version
}

output "security_group_id" {
  value = aws_security_group.nifi.id
}

output "instance_id" {
  value = try(module.nifi_instance[0].id, null)
}

output "nifi_url" {
  description = "NiFi UI URL (null when no instance is created)."
  value = try(
    "https://${coalesce(module.nifi_instance[0].public_ip, module.nifi_instance[0].private_ip)}:${local.nifi_https_port}/nifi",
    null
  )
}

output "effective_nifi_properties" {
  description = "Final nifi.properties overrides after merging defaults with var.nifi_properties."
  value       = local.nifi_properties
  sensitive   = true
}
