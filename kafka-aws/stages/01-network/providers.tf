terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
  # To share state with a team, replace with an S3 backend (see README).
  backend "local" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = var.project, ManagedBy = "terraform", Stage = local.stage }
  }
}

# ---- common variables (values come from ../../common.tfvars) ----
variable "project" { type = string }
variable "region" { type = string }
variable "domain_name" { type = string }

locals {
  keycloak_host = "keycloak.${var.domain_name}"
  kafka_ui_host = "kafka.${var.domain_name}"
}
