terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ------------------------------------------------------------
# VPC
# ------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "works-vpc"
  }
}

# ------------------------------------------------------------
# Internet Gateway
# ------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "works-igw"
  }
}

# ------------------------------------------------------------
# Get available AZs
# ------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------
# Public subnet 1
# ------------------------------------------------------------

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "works-public-a"
  }
}

# ------------------------------------------------------------
# Public subnet 2
#
# ALB needs two Availability Zones.
# ------------------------------------------------------------

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "works-public-b"
  }
}

# ------------------------------------------------------------
# Route table
# ------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "works-public-route"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------
# ALB Security Group
#
# Allow HTTP from the Internet.
# ------------------------------------------------------------

resource "aws_security_group" "alb" {
  name   = "works-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from Internet"

    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "works-alb-sg"
  }
}

# ------------------------------------------------------------
# Application Load Balancer
# ------------------------------------------------------------

resource "aws_lb" "works" {
  name               = "works-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name = "works-alb"
  }
}

# ------------------------------------------------------------
# HTTP Listener
#
# There is NO target group.
#
# The ALB itself returns:
#
# HTTP 200
# works
# ------------------------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.works.arn

  port     = 80
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "works"
      status_code  = "200"
    }
  }
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------

output "public_url" {
  value = "http://${aws_lb.works.dns_name}"
}

output "test_command" {
  value = "curl -i http://${aws_lb.works.dns_name}"
}