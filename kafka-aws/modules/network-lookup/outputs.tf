output "vpc_id" { value = data.aws_vpc.this.id }
output "private_subnet_ids" { value = sort(data.aws_subnets.private.ids) }
output "alb_security_group_id" { value = data.aws_security_group.alb.id }
output "alb_dns_name" { value = data.aws_lb.this.dns_name }
output "alb_zone_id" { value = data.aws_lb.this.zone_id }
output "https_listener_arn" { value = data.aws_lb_listener.https.arn }
output "zone_id" { value = data.aws_route53_zone.this.zone_id }
