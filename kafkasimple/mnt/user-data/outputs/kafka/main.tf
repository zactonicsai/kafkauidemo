###############################################################################
# kafka/main.tf  —  RUN THIS SECOND (after ../keycloak)
#
# Reuses the VPC/subnet created by the keycloak stack (found by Name tag),
# looks up the Keycloak instance's private IP, and launches an EC2 running
# Kafka (KRaft, single node) + Kafka UI via docker compose. Kafka UI
# authenticates against Keycloak at mykeycloak.demo.test over the private
# network; the hostname is pinned to Keycloak's private IP via extra_hosts.
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
variable "instance_type" { default = "t3.medium" }
variable "key_name"      { default = "" }
variable "allowed_cidr"  { default = "0.0.0.0/0" }   # tighten to your IP/32 for Kafka UI + SSH
variable "keycloak_hostname" { default = "mykeycloak.demo.test" }

# --- placeholders: must match what was used in ../keycloak ---
variable "kafka_ui_client_id"     { default = "kafka-ui" }
variable "kafka_ui_client_secret" { default = "CHANGE_ME_KAFKA_UI_CLIENT_SECRET" }

# ---------------------------- lookups from keycloak stack --------------------
data "aws_vpc" "shared" {
  filter {
    name   = "tag:Name"
    values = ["kafka-demo-vpc"]
  }
}

data "aws_subnet" "shared" {
  filter {
    name   = "tag:Name"
    values = ["kafka-demo-subnet"]
  }
}

data "aws_instance" "keycloak" {
  filter {
    name   = "tag:Role"
    values = ["keycloak"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# ---------------------------- security group ---------------------------------
resource "aws_security_group" "kafka" {
  name        = "kafka-ui-sg"
  description = "Kafka + Kafka UI"
  vpc_id      = data.aws_vpc.shared.id

  ingress {
    description = "Kafka UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    description = "Kafka broker from inside VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.shared.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "kafka-ui-sg" }
}

# ---------------------------- user data --------------------------------------
locals {
  keycloak_ip = data.aws_instance.keycloak.private_ip
  issuer_uri  = "http://${var.keycloak_hostname}:8080/realms/kafka"

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # Host-level resolution of the Keycloak hostname (private IP)
    echo "${local.keycloak_ip} ${var.keycloak_hostname}" >> /etc/hosts

    mkdir -p /opt/kafka
    cat > /opt/kafka/.env <<'ENV'
    # ---- placeholders: update and `docker compose up -d` to apply ----
    KAFKA_UI_CLIENT_ID=${var.kafka_ui_client_id}
    KAFKA_UI_CLIENT_SECRET=${var.kafka_ui_client_secret}
    KEYCLOAK_ISSUER_URI=${local.issuer_uri}
    ENV

    cat > /opt/kafka/docker-compose.yml <<'COMPOSE'
    services:
      kafka:
        image: apache/kafka:3.8.0
        container_name: kafka
        restart: unless-stopped
        environment:
          KAFKA_NODE_ID: 1
          KAFKA_PROCESS_ROLES: broker,controller
          KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
          KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
          KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
          KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
          KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
          KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
          KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
          KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
          KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
          KAFKA_LOG_DIRS: /var/lib/kafka/data
        ports:
          - "9092:9092"
        volumes:
          - kafka-data:/var/lib/kafka/data

      kafka-ui:
        image: provectuslabs/kafka-ui:latest
        container_name: kafka-ui
        restart: unless-stopped
        depends_on:
          - kafka
        ports:
          - "8080:8080"
        extra_hosts:
          - "${var.keycloak_hostname}:${local.keycloak_ip}"
        environment:
          KAFKA_CLUSTERS_0_NAME: local
          KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:9092
          DYNAMIC_CONFIG_ENABLED: "true"
          # ---- OIDC via external Keycloak ----
          AUTH_TYPE: OAUTH2
          AUTH_OAUTH2_CLIENT_KEYCLOAK_CLIENTID: $${KAFKA_UI_CLIENT_ID}
          AUTH_OAUTH2_CLIENT_KEYCLOAK_CLIENTSECRET: $${KAFKA_UI_CLIENT_SECRET}
          AUTH_OAUTH2_CLIENT_KEYCLOAK_SCOPE: openid
          AUTH_OAUTH2_CLIENT_KEYCLOAK_ISSUER_URI: $${KEYCLOAK_ISSUER_URI}
          AUTH_OAUTH2_CLIENT_KEYCLOAK_USER_NAME_ATTRIBUTE: preferred_username
          AUTH_OAUTH2_CLIENT_KEYCLOAK_CLIENT_NAME: keycloak
          AUTH_OAUTH2_CLIENT_KEYCLOAK_PROVIDER: keycloak
          AUTH_OAUTH2_CLIENT_KEYCLOAK_CUSTOM_PARAMS_TYPE: oauth

    volumes:
      kafka-data: {}
    COMPOSE

    cd /opt/kafka && docker compose up -d
  EOF
}

# ---------------------------- instance ---------------------------------------
resource "aws_instance" "kafka" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.shared.id
  vpc_security_group_ids      = [aws_security_group.kafka.id]
  associate_public_ip_address = true
  key_name                    = var.key_name != "" ? var.key_name : null
  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device { volume_size = 30 }

  tags = { Name = "kafka-kafka-ui", Role = "kafka" }
}

# ---------------------------- outputs ----------------------------------------
output "kafka_ui_url"         { value = "http://${aws_instance.kafka.public_ip}:8080" }
output "kafka_private_ip"     { value = aws_instance.kafka.private_ip }
output "keycloak_private_ip"  { value = local.keycloak_ip }
output "keycloak_issuer_used" { value = local.issuer_uri }
