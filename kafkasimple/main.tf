###############################################################################
# keycloak/main.tf  —  RUN THIS FIRST
#
# Creates the shared VPC/subnet and a Keycloak EC2 (start-dev, HTTP only,
# no certs). Inbound is allowed ONLY from inside the VPC CIDR, so Keycloak
# is reachable by the Kafka/Kafka-UI instance on the private network but
# not from the internet. A "kafka" realm with a "kafka-ui" client is
# imported at boot.
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

# ---------------------------- variables --------------------------------------
variable "region"        { default = "us-east-1" }
variable "vpc_cidr"      { default = "10.20.0.0/16" }
variable "subnet_cidr"   { default = "10.20.1.0/24" }
variable "instance_type" { default = "t3.small" }
variable "key_name"      { default = "" }            # optional; SSH is only from inside the VPC anyway
variable "keycloak_hostname" { default = "mykeycloak.demo.test" }

# --- placeholders: update before apply or pass with -var ---
variable "keycloak_admin_user"     { default = "admin" }
variable "keycloak_admin_password" { default = "CHANGE_ME_KEYCLOAK_ADMIN_PASSWORD" }
variable "kafka_ui_client_secret"  { default = "CHANGE_ME_KAFKA_UI_CLIENT_SECRET" }
variable "demo_user_password"      { default = "CHANGE_ME_DEMO_USER_PASSWORD" }

# ---------------------------- network ----------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "kafka-demo-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "kafka-demo-igw" }
}

# Single subnet shared by both stacks. Instances get a public IP purely for
# egress (docker pulls); Keycloak's SG blocks all inbound from outside the VPC.
resource "aws_subnet" "this" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  tags = { Name = "kafka-demo-subnet" }
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "kafka-demo-rt" }
}

resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}

# Private-only security group: 8080 and 22 from the VPC CIDR only.
resource "aws_security_group" "keycloak" {
  name        = "keycloak-private-sg"
  description = "Keycloak - reachable only from inside the VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Keycloak HTTP from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "keycloak-private-sg" }
}

# ---------------------------- AMI --------------------------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# ---------------------------- user data --------------------------------------
locals {
  realm_json = jsonencode({
    realm   = "kafka"
    enabled = true
    clients = [{
      clientId                  = "kafka-ui"
      name                      = "Kafka UI"
      enabled                   = true
      protocol                  = "openid-connect"
      publicClient              = false
      clientAuthenticatorType   = "client-secret"
      secret                    = var.kafka_ui_client_secret
      standardFlowEnabled       = true
      directAccessGrantsEnabled = false
      redirectUris              = ["*"]
      webOrigins                = ["*"]
      defaultClientScopes       = ["openid", "profile", "email", "roles"]
    }]
    users = [{
      username      = "demo"
      enabled       = true
      email         = "demo@demo.test"
      emailVerified = true
      firstName     = "Demo"
      lastName      = "User"
      credentials   = [{ type = "password", value = var.demo_user_password, temporary = false }]
    }]
  })

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    # Docker + compose plugin
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    mkdir -p /opt/keycloak/import
    cat > /opt/keycloak/import/kafka-realm.json <<'REALM'
    ${local.realm_json}
    REALM

    cat > /opt/keycloak/docker-compose.yml <<'COMPOSE'
    services:
      keycloak:
        image: quay.io/keycloak/keycloak:26.0
        container_name: keycloak
        command: ["start-dev", "--import-realm"]
        restart: unless-stopped
        environment:
          KC_BOOTSTRAP_ADMIN_USERNAME: "${var.keycloak_admin_user}"
          KC_BOOTSTRAP_ADMIN_PASSWORD: "${var.keycloak_admin_password}"
          KC_HOSTNAME: "${var.keycloak_hostname}"
          KC_HOSTNAME_STRICT: "false"
          KC_HTTP_ENABLED: "true"
          KC_HTTP_PORT: "8080"
        ports:
          - "8080:8080"
        volumes:
          - ./import:/opt/keycloak/data/import:ro
          - keycloak-data:/opt/keycloak/data
    volumes:
      keycloak-data: {}
    COMPOSE

    cd /opt/keycloak && docker compose up -d
  EOF
}

# ---------------------------- instance ---------------------------------------
resource "aws_instance" "keycloak" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.this.id
  vpc_security_group_ids      = [aws_security_group.keycloak.id]
  associate_public_ip_address = true # egress only; SG blocks internet inbound
  key_name                    = var.key_name != "" ? var.key_name : null
  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device { volume_size = 20 }

  tags = { Name = "keycloak", Role = "keycloak" }
}

# ---------------------------- outputs ----------------------------------------
output "vpc_id"               { value = aws_vpc.this.id }
output "subnet_id"            { value = aws_subnet.this.id }
output "keycloak_private_ip"  { value = aws_instance.keycloak.private_ip }
output "keycloak_private_url" { value = "http://${var.keycloak_hostname}:8080  (resolves to ${aws_instance.keycloak.private_ip} inside the VPC)" }
output "realm_issuer"         { value = "http://${var.keycloak_hostname}:8080/realms/kafka" }
