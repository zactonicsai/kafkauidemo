output "kafka_ui_url" { value = module.kafka_ui_service.url }
output "instance_id" { value = module.kafka.instance_id }
output "target_group_arn" { value = module.kafka_ui_service.target_group_arn }
output "kafka_bootstrap_private" {
  description = "Only reachable from inside the VPC (add a security-group rule first)"
  value       = "${module.kafka.private_ip}:9092"
}
