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

variable "kafka_instance_type" {
  description = "EC2 size for Kafka + Kafka UI."
  type        = string
  default     = "t3.medium"
}

variable "keycloak_instance_type" {
  description = "EC2 size for Keycloak. t3.small is fine for this lab."
  type        = string
  default     = "t3.small"
}

variable "allowed_cidr" {
  description = "IPv4 CIDR allowed to open Kafka UI and Keycloak. YOUR_PUBLIC_IP/32 is recommended."
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

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

###############################################################################
# FIND AN AVAILABILITY ZONE THAT SUPPORTS BOTH INSTANCE TYPES
#
# Do not let AWS randomly choose the subnet AZ. Some EC2 instance types are
# not offered in every Availability Zone. We ask EC2 which AZs support each
# requested size, then select the first AZ common to both lists.
###############################################################################

data "aws_ec2_instance_type_offerings" "kafka" {
  filter {
    name   = "instance-type"
    values = [var.kafka_instance_type]
  }

  location_type = "availability-zone"
}

data "aws_ec2_instance_type_offerings" "keycloak" {
  filter {
    name   = "instance-type"
    values = [var.keycloak_instance_type]
  }

  location_type = "availability-zone"
}

locals {
  common_instance_azs = sort(tolist(setintersection(
    toset(data.aws_ec2_instance_type_offerings.kafka.locations),
    toset(data.aws_ec2_instance_type_offerings.keycloak.locations)
  )))

  selected_availability_zone = try(local.common_instance_azs[0], null)
}

###############################################################################
# RANDOM LAB PASSWORDS / OIDC SECRET
###############################################################################

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
  availability_zone       = local.selected_availability_zone
  map_public_ip_on_launch = true

  lifecycle {
    precondition {
      condition     = local.selected_availability_zone != null
      error_message = "No Availability Zone in ${var.aws_region} supports both ${var.kafka_instance_type} and ${var.keycloak_instance_type}. Choose different instance types."
    }
  }

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
# SECURITY GROUPS
###############################################################################

# Kafka host: only Kafka UI is public. Kafka itself remains inside Docker.
resource "aws_security_group" "kafka" {
  name_prefix = "${var.project_name}-kafka-"
  description = "Kafka and Kafka UI EC2 access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Kafka UI from allowed client network"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "Outbound access for packages, images, and Keycloak OIDC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-kafka-sg"
  }
}

# Keycloak host: browser access is limited to allowed_cidr. Kafka UI is also
# explicitly allowed to reach Keycloak over the VPC private network.
resource "aws_security_group" "keycloak" {
  name_prefix = "${var.project_name}-keycloak-"
  description = "Keycloak EC2 access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Keycloak HTTPS browser/admin access"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description     = "Kafka UI private OIDC HTTPS back-channel"
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    security_groups = [aws_security_group.kafka.id]
  }

  # Lab-only access to Keycloak management endpoints. Keep this restricted to
  # allowed_cidr; Keycloak recommends not exposing port 9000 broadly.
  ingress {
    description = "Keycloak health and metrics from allowed client network"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "Outbound Internet access for packages and images"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-keycloak-sg"
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
# STABLE PUBLIC IPS
###############################################################################

resource "aws_eip" "kafka" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-kafka-eip"
  }
}

resource "aws_eip" "keycloak" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-keycloak-eip"
  }
}

###############################################################################
# CONFIGURATION RENDERED INTO EACH EC2 USER-DATA SCRIPT
###############################################################################

locals {
  # Keycloak realm contains the Kafka UI OIDC client and demo user.
  keycloak_realm = templatefile("${path.module}/files/keycloak-realm.json.tftpl", {
    kafka_public_ip  = aws_eip.kafka.public_ip
    kafka_ui_username = var.kafka_ui_username
    kafka_ui_password = random_password.kafka_ui_user.result
    kafka_ui_secret   = random_password.kafka_ui_client_secret.result
  })

  # Kafka UI uses HTTPS for every Keycloak OIDC endpoint. Browser authorization uses
  # the stable Keycloak EIP; token/JWK/userinfo calls use the Keycloak private IP.
  kafka_ui_config = templatefile("${path.module}/files/kafka-ui.yml.tftpl", {
    kafka_public_ip          = aws_eip.kafka.public_ip
    keycloak_public_ip       = aws_eip.keycloak.public_ip
    keycloak_private_ip      = aws_instance.keycloak.private_ip
    kafka_ui_secret          = random_password.kafka_ui_client_secret.result
  })

  kafka_compose = templatefile("${path.module}/files/docker-compose.yml.tftpl", {})

  keycloak_compose = templatefile("${path.module}/files/keycloak-compose.yml.tftpl", {
    keycloak_public_ip       = aws_eip.keycloak.public_ip
    keycloak_admin_username  = var.keycloak_admin_username
    keycloak_admin_password  = random_password.keycloak_admin.result
  })

  kafka_user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    docker_compose_b64  = base64encode(local.kafka_compose)
    kafka_ui_config_b64 = base64encode(local.kafka_ui_config)
    keycloak_private_ip = aws_instance.keycloak.private_ip
  })

  keycloak_user_data = templatefile("${path.module}/templates/keycloak_user_data.sh.tftpl", {
    keycloak_compose_b64 = base64encode(local.keycloak_compose)
    keycloak_realm_b64   = base64encode(local.keycloak_realm)
    keycloak_public_ip   = aws_eip.keycloak.public_ip
  })
}

###############################################################################
# KEYCLOAK LAUNCH TEMPLATE + EC2
###############################################################################

resource "aws_launch_template" "keycloak" {
  name_prefix            = "${var.project_name}-keycloak-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.keycloak_instance_type
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    delete_on_termination       = true
    subnet_id                   = aws_subnet.public.id
    security_groups             = [aws_security_group.keycloak.id]
  }

  user_data = base64encode(local.keycloak_user_data)

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = 20
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
      Name = "${var.project_name}-keycloak-ec2"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project_name}-keycloak-root"
    }
  }

  tags = {
    Name = "${var.project_name}-keycloak-launch-template"
  }
}

resource "aws_instance" "keycloak" {
  launch_template {
    id      = aws_launch_template.keycloak.id
    version = tostring(aws_launch_template.keycloak.latest_version)
  }

  tags = {
    Name = "${var.project_name}-keycloak-ec2"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_route_table_association.public
  ]
}

resource "aws_eip_association" "keycloak" {
  instance_id   = aws_instance.keycloak.id
  allocation_id = aws_eip.keycloak.id
}

###############################################################################
# KAFKA + KAFKA UI LAUNCH TEMPLATE + EC2
###############################################################################

resource "aws_launch_template" "kafka" {
  name_prefix            = "${var.project_name}-kafka-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.kafka_instance_type
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    delete_on_termination       = true
    subnet_id                   = aws_subnet.public.id
    security_groups             = [aws_security_group.kafka.id]
  }

  user_data = base64encode(local.kafka_user_data)

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
      Name = "${var.project_name}-kafka-ec2"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project_name}-kafka-root"
    }
  }

  tags = {
    Name = "${var.project_name}-kafka-launch-template"
  }
}

resource "aws_instance" "kafka" {
  launch_template {
    id      = aws_launch_template.kafka.id
    version = tostring(aws_launch_template.kafka.latest_version)
  }

  tags = {
    Name = "${var.project_name}-kafka-ec2"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_route_table_association.public,
    aws_instance.keycloak,
    aws_eip_association.keycloak
  ]
}

resource "aws_eip_association" "kafka" {
  instance_id   = aws_instance.kafka.id
  allocation_id = aws_eip.kafka.id
}

###############################################################################
# OUTPUTS
###############################################################################

output "selected_availability_zone" {
  value       = local.selected_availability_zone
  description = "Availability Zone selected because it supports both configured EC2 instance types."
}

output "supported_common_availability_zones" {
  value       = local.common_instance_azs
  description = "Availability Zones that support both Kafka and Keycloak instance types."
}

output "kafka_instance_id" {
  value       = aws_instance.kafka.id
  description = "EC2 instance running Kafka and Kafka UI."
}

output "keycloak_instance_id" {
  value       = aws_instance.keycloak.id
  description = "EC2 instance running Keycloak."
}

output "kafka_public_ip" {
  value       = aws_eip.kafka.public_ip
  description = "Stable public IPv4 address for Kafka UI."
}

output "keycloak_public_ip" {
  value       = aws_eip.keycloak.public_ip
  description = "Stable public IPv4 address for Keycloak."
}

output "keycloak_private_ip" {
  value       = aws_instance.keycloak.private_ip
  description = "Private VPC address used by Kafka UI for OIDC back-channel calls."
}

output "kafka_ui_url" {
  value       = "http://${aws_eip.kafka.public_ip}:8080"
  description = "Kafka UI URL. Keycloak handles login."
}

output "keycloak_url" {
  value       = "https://${aws_eip.keycloak.public_ip}:8443"
  description = "Keycloak HTTPS base URL. Uses the lab self-signed certificate."
}

output "keycloak_admin_url" {
  value       = "https://${aws_eip.keycloak.public_ip}:8443/admin/"
  description = "Keycloak HTTPS Admin Console."
}

output "keycloak_metrics_url" {
  value       = "https://${aws_eip.keycloak.public_ip}:9000/metrics"
  description = "Keycloak metrics endpoint. Restricted by allowed_cidr."
}

output "keycloak_health_url" {
  value       = "https://${aws_eip.keycloak.public_ip}:9000/health/ready"
  description = "Keycloak readiness endpoint. Restricted by allowed_cidr."
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

output "ssm_kafka" {
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.kafka.id}"
  description = "SSM command for Kafka/Kafka UI EC2."
}

output "ssm_keycloak" {
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.keycloak.id}"
  description = "SSM command for Keycloak EC2."
}
