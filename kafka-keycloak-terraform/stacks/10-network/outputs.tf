output "aws_region" {
  value = var.aws_region
}

output "project_name" {
  value = var.project_name
}

output "selected_availability_zone" {
  description = "AZ used for subnets that did not pin their own."
  value       = local.selected_availability_zone
}

output "supported_common_availability_zones" {
  value = local.common_azs
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Map: subnet key => id."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "public_subnet_azs" {
  value = module.vpc.public_subnet_azs
}

output "security_group_ids" {
  description = "Map: security group key => id."
  value       = module.security_groups.security_group_ids
}

output "instance_profile_names" {
  description = "Map: role key => instance profile name."
  value       = { for k, m in module.instance_roles : k => m.instance_profile_name }
}

output "iam_role_arns" {
  value = { for k, m in module.instance_roles : k => m.role_arn }
}
