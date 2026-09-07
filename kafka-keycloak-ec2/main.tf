terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

###############################################################################
# VARIABLES
###############################################################################

variable "aws_region" {
  description = "AWS region used for the lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used on AWS resources."
  type        = string
  default     = "kafka-keycloak-lab"
}

variable "instance_type" {
  description = "EC2 size. t3.medium is a reasonable minimum for Kafka + Kafka UI + Keycloak on one host."
  type        = string
  default     = "t3.medium"
}

variable "allowed_cidr" {
  description = "IPv4 CIDR allowed to open Kafka UI and Keycloak. For a lab 0.0.0.0/0 works, but YOUR_PUBLIC_IP/32 is safer."
  type        = string
  default     = "0.0.0.0/0"
}

variable "kafka_ui_username" {
  description = "User imported into the Keycloak kafka-ui realm."
  type        = string
  default     = "kafkauser"
}

variable "keycloak_admin_username" {
  description = "Initial Keycloak administrator username."
  type        = string
  default     = "admin"
}

###############################################################################
# CURRENT AMAZON LINUX 2023 AMI
###############################################################################

# AWS maintains this SSM public parameter, so an AMI ID does not need to be
# hard-coded in this Terraform configuration.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

###############################################################################
# RANDOM LAB PASSWORDS
###############################################################################

# Alphanumeric values keep the generated JSON/YAML and shell bootstrapping
# simple. These values still end up in Terraform state, so this is a LAB
# pattern, not a production secret-management design.
resource "random_password" "keycloak_admin" {
  length  = 24
  special = false
}

resource "random_password" "kafka_ui_user" {
  length  = 20
  special = false
}

resource "random_password" "kafka_ui_client_secret" {
  length  = 32
  special = false
}

###############################################################################
# NETWORK
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# SECURITY GROUP
###############################################################################

resource "aws_security_group" "stack" {
  name_prefix = "${var.project_name}-"
  description = "Kafka UI and Keycloak lab access"
  vpc_id      = aws_vpc.main.id

  # Kafka UI
  ingress {
    description = "Kafka UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Keycloak web/admin console
  ingress {
    description = "Keycloak"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Kafka port 9092 is intentionally NOT exposed publicly.
  # Kafka UI reaches Kafka through Docker's private bridge network.

  egress {
    description = "Allow outbound Internet access for package/image downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

###############################################################################
# IAM FOR SSM SESSION MANAGER
###############################################################################

resource "aws_iam_role" "ec2_ssm" {
  name_prefix = "${var.project_name}-ssm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${var.project_name}-"
  role        = aws_iam_role.ec2_ssm.name
}

###############################################################################
# STABLE PUBLIC IP
###############################################################################

# OAuth callback URLs must match. An Elastic IP gives this lab a stable address
# even if the EC2 instance is stopped and started.
resource "aws_eip" "stack" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

###############################################################################
# CONFIG FILES RENDERED INTO EC2 USER DATA
###############################################################################

locals {
  docker_compose = templatefile("${path.module}/files/docker-compose.yml.tftpl", {
    public_ip                  = aws_eip.stack.public_ip
    keycloak_admin_username   = var.keycloak_admin_username
    keycloak_admin_password   = random_password.keycloak_admin.result
  })

  keycloak_realm = templatefile("${path.module}/files/keycloak-realm.json.tftpl", {
    public_ip          = aws_eip.stack.public_ip
    kafka_ui_username  = var.kafka_ui_username
    kafka_ui_password  = random_password.kafka_ui_user.result
    kafka_ui_secret    = random_password.kafka_ui_client_secret.result
  })

  kafka_ui_config = templatefile("${path.module}/files/kafka-ui.yml.tftpl", {
    public_ip       = aws_eip.stack.public_ip
    kafka_ui_secret = random_password.kafka_ui_client_secret.result
  })

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    docker_compose_b64 = base64encode(local.docker_compose)
    keycloak_realm_b64 = base64encode(local.keycloak_realm)
    kafka_ui_config_b64 = base64encode(local.kafka_ui_config)
  })
}

###############################################################################
# EC2 LAUNCH TEMPLATE
###############################################################################

# Keep the EC2 definition in a Launch Template.  This makes the machine setup
# reusable later if you decide to put it behind an Auto Scaling Group.
resource "aws_launch_template" "stack" {
  name_prefix            = "${var.project_name}-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.stack.id]

  # Launch Templates expect user_data to already be base64 encoded.
  user_data = base64encode(local.user_data)

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = 30
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-ec2"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  tags = {
    Name = "${var.project_name}-launch-template"
  }
}

###############################################################################
# EC2 INSTANCE FROM THE LAUNCH TEMPLATE
###############################################################################

resource "aws_instance" "stack" {
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true

  launch_template {
    id      = aws_launch_template.stack.id
    version = tostring(aws_launch_template.stack.latest_version)
  }

  # Changing the Launch Template creates a new LT version.  Referencing the
  # numeric latest_version here makes Terraform replace the EC2 instance so the
  # new boot configuration is actually applied.
  tags = {
    Name = "${var.project_name}-ec2"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_route_table_association.public
  ]
}

resource "aws_eip_association" "stack" {
  instance_id   = aws_instance.stack.id
  allocation_id = aws_eip.stack.id
}

###############################################################################
# OUTPUTS
###############################################################################

output "launch_template_id" {
  value       = aws_launch_template.stack.id
  description = "EC2 Launch Template used by the lab instance."
}

output "instance_id" {
  value       = aws_instance.stack.id
  description = "EC2 instance created from the Launch Template."
}

output "public_ip" {
  value       = aws_eip.stack.public_ip
  description = "Stable public IPv4 address for this lab."
}

output "kafka_ui_url" {
  value       = "http://${aws_eip.stack.public_ip}:8080"
  description = "Open this URL to use Kafka UI. Keycloak should handle login."
}

output "keycloak_url" {
  value       = "http://${aws_eip.stack.public_ip}:8081"
  description = "Keycloak base URL."
}

output "keycloak_admin_url" {
  value       = "http://${aws_eip.stack.public_ip}:8081/admin/"
  description = "Keycloak Admin Console."
}

output "kafka_ui_username" {
  value       = var.kafka_ui_username
  description = "Demo Keycloak user for Kafka UI."
}

output "kafka_ui_user_password" {
  value       = random_password.kafka_ui_user.result
  sensitive   = true
  description = "Password for the imported Kafka UI user."
}

output "keycloak_admin_username" {
  value       = var.keycloak_admin_username
  description = "Keycloak administrator username."
}

output "keycloak_admin_password" {
  value       = random_password.keycloak_admin.result
  sensitive   = true
  description = "Generated Keycloak administrator password."
}

output "ssm_start_session" {
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.stack.id}"
  description = "Connect without opening SSH port 22."
}
