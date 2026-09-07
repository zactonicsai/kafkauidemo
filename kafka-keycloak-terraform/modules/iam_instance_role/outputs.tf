output "role_name" {
  value = aws_iam_role.this.name
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.this.name
}

output "instance_profile_arn" {
  value = aws_iam_instance_profile.this.arn
}

output "policy_attachment_ids" {
  description = "Useful for depends_on so instances start only after policies are attached."
  value       = [for a in aws_iam_role_policy_attachment.managed : a.id]
}
