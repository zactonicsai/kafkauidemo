output "security_group_ids" {
  description = "Map of security group key => id."
  value       = { for k, sg in aws_security_group.this : k => sg.id }
}

output "security_group_arns" {
  value = { for k, sg in aws_security_group.this : k => sg.arn }
}
