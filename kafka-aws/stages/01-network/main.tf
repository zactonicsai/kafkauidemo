# STAGE 1: VPC + networking + hosted zone + certificate + public ALB (the gateway).
locals { stage = "01-network" }

module "vpc" {
  source  = "../../modules/vpc"
  project = var.project
  cidr    = var.vpc_cidr
}

module "dns" {
  source            = "../../modules/dns"
  project           = var.project
  domain_name       = var.domain_name
  certificate_hosts = [local.keycloak_host, local.kafka_ui_host]
}

module "alb" {
  source            = "../../modules/alb"
  project           = var.project
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = module.dns.certificate_arn
}
