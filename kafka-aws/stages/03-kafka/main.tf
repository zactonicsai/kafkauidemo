# STAGE 3: Kafka broker + Kafka UI on one private EC2, published as https://kafka.<domain>.
# Reads Keycloak's issuer URL and client secret from SSM (written by stage 02).
locals { stage = "03-kafka" }

module "network" {
  source      = "../../modules/network-lookup"
  project     = var.project
  domain_name = var.domain_name
}

data "aws_ssm_parameter" "issuer_url" { name = "/${var.project}/keycloak/issuer-url" }
data "aws_ssm_parameter" "client_secret" {
  name            = "/${var.project}/keycloak/kafka-ui-client-secret"
  with_decryption = true
}

module "kafka" {
  source                = "../../modules/ec2-docker"
  project               = var.project
  name                  = "kafka"
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.private_subnet_ids[1]
  alb_security_group_id = module.network.alb_security_group_id
  ingress_ports         = [8090]
  instance_type         = var.instance_type
  root_volume_gb        = var.root_volume_gb
  app_script = templatefile("${path.module}/user_data.sh.tftpl", {
    kafka_ui_host          = local.kafka_ui_host
    keycloak_issuer_url    = data.aws_ssm_parameter.issuer_url.value
    keycloak_client_secret = data.aws_ssm_parameter.client_secret.value
  })
}

module "kafka_ui_service" {
  source             = "../../modules/alb-service"
  project            = var.project
  name               = "kafka-ui"
  vpc_id             = module.network.vpc_id
  instance_id        = module.kafka.instance_id
  port               = 8090
  health_check_path  = "/actuator/health"
  hostname           = local.kafka_ui_host
  priority           = 20
  https_listener_arn = module.network.https_listener_arn
  alb_dns_name       = module.network.alb_dns_name
  alb_zone_id        = module.network.alb_zone_id
  zone_id            = module.network.zone_id
}
