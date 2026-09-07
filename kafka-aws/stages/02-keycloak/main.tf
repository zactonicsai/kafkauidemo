# STAGE 2: Keycloak on its own private EC2, published as https://keycloak.<domain>.
# Publishes the client secret + issuer URL to SSM Parameter Store for stage 03.
locals { stage = "02-keycloak" }

module "network" {
  source      = "../../modules/network-lookup"
  project     = var.project
  domain_name = var.domain_name
}

module "keycloak" {
  source                = "../../modules/ec2-docker"
  project               = var.project
  name                  = "keycloak"
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.private_subnet_ids[0]
  alb_security_group_id = module.network.alb_security_group_id
  ingress_ports         = [8080]
  instance_type         = var.instance_type
  root_volume_gb        = 20
  app_script = templatefile("${path.module}/user_data.sh.tftpl", {
    keycloak_host           = local.keycloak_host
    kafka_ui_host           = local.kafka_ui_host
    keycloak_admin_password = var.keycloak_admin_password
    keycloak_client_secret  = var.keycloak_client_secret
    alice_password          = var.alice_password
    bob_password            = var.bob_password
  })
}

module "keycloak_service" {
  source             = "../../modules/alb-service"
  project            = var.project
  name               = "keycloak"
  vpc_id             = module.network.vpc_id
  instance_id        = module.keycloak.instance_id
  port               = 8080
  health_check_path  = "/realms/kafka"
  hostname           = local.keycloak_host
  priority           = 10
  https_listener_arn = module.network.https_listener_arn
  alb_dns_name       = module.network.alb_dns_name
  alb_zone_id        = module.network.alb_zone_id
  zone_id            = module.network.zone_id
}

# ---- hand-off to stage 03 (no shared state needed) ----
resource "aws_ssm_parameter" "issuer_url" {
  name  = "/${var.project}/keycloak/issuer-url"
  type  = "String"
  value = "https://${local.keycloak_host}/realms/kafka"
}

resource "aws_ssm_parameter" "client_secret" {
  name  = "/${var.project}/keycloak/kafka-ui-client-secret"
  type  = "SecureString"
  value = var.keycloak_client_secret
}
