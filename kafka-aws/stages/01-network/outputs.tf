output "name_servers" {
  description = "Set these NS records at your domain registrar"
  value       = module.dns.name_servers
}
output "hosted_zone_id" { value = module.dns.zone_id }
output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnet_ids }
output "alb_dns_name" { value = module.alb.alb_dns_name }
output "nat_public_ip" { value = module.vpc.nat_public_ip }
