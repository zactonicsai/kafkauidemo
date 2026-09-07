###############################################################################
# APPS STACK (process 2)
#
# Keycloak and Kafka + Kafka UI EC2 instances built from the base
# launch_template / ec2_instance / elastic_ip modules, on top of the network
# created by stacks/10-network.
###############################################################################

###############################################################################
# SECRETS
###############################################################################

resource "random_password" "keycloak_admin" {
  count   = var.keycloak.admin_password == null ? 1 : 0
  length  = 24
  special = false
}

resource "random_password" "kafka_ui_user" {
  count   = var.kafka.ui_password == null ? 1 : 0
  length  = 20
  special = false
}

resource "random_password" "kafka_ui_client_secret" {
  length  = 32
  special = false
}

###############################################################################
# STABLE PUBLIC IPS (allocated first so user-data can embed them)
###############################################################################

module "keycloak_eip" {
  source = "../../modules/elastic_ip"
  count  = var.keycloak.enabled ? 1 : 0

  name = "${var.project_name}-keycloak"
  tags = var.tags
}

module "kafka_eip" {
  source = "../../modules/elastic_ip"
  count  = var.kafka.enabled ? 1 : 0

  name = "${var.project_name}-kafka"
  tags = var.tags
}

###############################################################################
# KEYCLOAK
###############################################################################

locals {
  keycloak_public_ip = try(module.keycloak_eip[0].public_ip, null)
  # Placeholder keeps the Keycloak realm template renderable when Kafka is disabled.
  kafka_public_ip = try(module.kafka_eip[0].public_ip, "kafka-ui.invalid")

  keycloak_realm = var.keycloak.enabled ? templatefile("${path.module}/files/keycloak-realm.json.tftpl", {
    kafka_public_ip   = local.kafka_public_ip
    kafka_ui_username = var.kafka.ui_username
    kafka_ui_password = local.kafka_ui_password
    kafka_ui_secret   = local.kafka_ui_client_secret
  }) : null

  keycloak_compose = var.keycloak.enabled ? templatefile("${path.module}/files/keycloak-compose.yml.tftpl", {
    keycloak_public_ip      = local.keycloak_public_ip
    keycloak_admin_username = var.keycloak.admin_username
    keycloak_admin_password = local.keycloak_admin_password
  }) : null

  keycloak_user_data = var.keycloak.enabled ? templatefile("${path.module}/templates/keycloak_user_data.sh.tftpl", {
    keycloak_compose_b64 = base64encode(local.keycloak_compose)
    keycloak_realm_b64   = base64encode(local.keycloak_realm)
    keycloak_public_ip   = local.keycloak_public_ip
  }) : null
}

module "keycloak_launch_template" {
  source = "../../modules/launch_template"
  count  = var.keycloak.enabled ? 1 : 0

  name                      = "${var.project_name}-keycloak"
  description               = "Keycloak host"
  image_id                  = local.ami_id
  instance_type             = var.keycloak.instance_type
  key_name                  = var.keycloak.key_name
  iam_instance_profile_name = local.instance_profile_name
  subnet_id                 = local.subnet_id
  security_group_ids        = local.keycloak_security_group_ids
  user_data                 = local.keycloak_user_data
  root_volume_size          = var.keycloak.root_volume_size
  root_volume_type          = var.keycloak.root_volume_type
  tags                      = merge(var.tags, var.keycloak.tags)
}

module "keycloak" {
  source = "../../modules/ec2_instance"
  count  = var.keycloak.enabled ? 1 : 0

  name                    = "${var.project_name}-keycloak"
  launch_template_id      = module.keycloak_launch_template[0].id
  launch_template_version = tostring(module.keycloak_launch_template[0].latest_version)
  eip_allocation_id       = module.keycloak_eip[0].allocation_id
  tags                    = merge(var.tags, var.keycloak.tags)
}

###############################################################################
# KAFKA + KAFKA UI
###############################################################################

locals {
  keycloak_private_ip = try(module.keycloak[0].private_ip, null)

  kafka_ui_config = var.kafka.enabled ? templatefile("${path.module}/files/kafka-ui.yml.tftpl", {
    kafka_public_ip     = local.kafka_public_ip
    keycloak_public_ip  = local.keycloak_public_ip
    keycloak_private_ip = local.keycloak_private_ip
    kafka_ui_secret     = local.kafka_ui_client_secret
  }) : null

  kafka_compose = var.kafka.enabled ? templatefile("${path.module}/files/docker-compose.yml.tftpl", {}) : null

  kafka_user_data = var.kafka.enabled ? templatefile("${path.module}/templates/user_data.sh.tftpl", {
    docker_compose_b64  = base64encode(local.kafka_compose)
    kafka_ui_config_b64 = base64encode(local.kafka_ui_config)
    keycloak_private_ip = local.keycloak_private_ip
  }) : null
}

module "kafka_launch_template" {
  source = "../../modules/launch_template"
  count  = var.kafka.enabled ? 1 : 0

  name                      = "${var.project_name}-kafka"
  description               = "Kafka + Kafka UI host"
  image_id                  = local.ami_id
  instance_type             = var.kafka.instance_type
  key_name                  = var.kafka.key_name
  iam_instance_profile_name = local.instance_profile_name
  subnet_id                 = local.subnet_id
  security_group_ids        = local.kafka_security_group_ids
  user_data                 = local.kafka_user_data
  root_volume_size          = var.kafka.root_volume_size
  root_volume_type          = var.kafka.root_volume_type
  tags                      = merge(var.tags, var.kafka.tags)
}

module "kafka" {
  source = "../../modules/ec2_instance"
  count  = var.kafka.enabled ? 1 : 0

  name                    = "${var.project_name}-kafka"
  launch_template_id      = module.kafka_launch_template[0].id
  launch_template_version = tostring(module.kafka_launch_template[0].latest_version)
  eip_allocation_id       = module.kafka_eip[0].allocation_id
  tags                    = merge(var.tags, var.kafka.tags)

  # Kafka UI fetches Keycloak's TLS certificate at boot, so Keycloak must be
  # up (and its EIP bound) before this instance starts.
  depends_on = [module.keycloak]
}

###############################################################################
# GUARD RAILS
###############################################################################

check "kafka_requires_keycloak" {
  assert {
    condition     = !var.kafka.enabled || var.keycloak.enabled
    error_message = "Kafka UI authenticates against Keycloak; enable keycloak when kafka is enabled."
  }
}
