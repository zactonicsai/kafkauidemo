# Finds everything created by stage 01-network by tag/name, so later stages
# do not need remote state and can be applied independently.
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = ["${var.project}-vpc"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

data "aws_security_group" "alb" {
  vpc_id = data.aws_vpc.this.id
  filter {
    name   = "group-name"
    values = ["${var.project}-alb"]
  }
}

data "aws_lb" "this" { name = "${var.project}-alb" }

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.this.arn
  port              = 443
}

data "aws_route53_zone" "this" { name = var.domain_name }
