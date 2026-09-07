output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  value = try(aws_internet_gateway.this[0].id, null)
}

output "public_subnet_ids" {
  description = "Map of public subnet key => subnet id."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "Map of private subnet key => subnet id."
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "public_subnet_azs" {
  value = { for k, s in aws_subnet.public : k => s.availability_zone }
}

output "public_route_table_id" {
  value = try(aws_route_table.public[0].id, null)
}

output "private_route_table_id" {
  value = try(aws_route_table.private[0].id, null)
}

output "nat_gateway_id" {
  value = try(aws_nat_gateway.this[0].id, null)
}
