variable "project" {
  description = "Name used for tags and resource names"
  type        = string
  default     = "kafka-stack"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain for the Route 53 hosted zone, e.g. example.com (you must own it)"
  type        = string
}

variable "instance_type" {
  description = "EC2 size. t3.medium (4 GB RAM) is the minimum for Kafka + Keycloak + Kafka UI"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_gb" {
  type    = number
  default = 30
}

variable "keycloak_admin_password" {
  type      = string
  sensitive = true
}

variable "keycloak_client_secret" {
  description = "Secret shared between Kafka UI and Keycloak"
  type      = string
  sensitive = true
}

variable "alice_password" {
  description = "Password for demo admin user 'alice'"
  type      = string
  sensitive = true
}

variable "bob_password" {
  description = "Password for demo read-only user 'bob'"
  type      = string
  sensitive = true
}

locals {
  keycloak_host = "keycloak.${var.domain_name}"
  kafka_ui_host = "kafka.${var.domain_name}"
  azs           = slice(data.aws_availability_zones.available.names, 0, 2)
}
