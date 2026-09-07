output "id" {
  value = aws_instance.this.id
}

output "arn" {
  value = aws_instance.this.arn
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "public_ip" {
  description = "EIP when associated, otherwise the instance's auto-assigned public IP."
  value       = try(aws_eip_association.this[0].public_ip, aws_instance.this.public_ip)
}

output "availability_zone" {
  value = aws_instance.this.availability_zone
}
