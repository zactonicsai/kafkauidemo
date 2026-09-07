locals {
  # Only read remote state when at least one network value is not overridden.
  needs_remote_state = anytrue([
    var.network.subnet_id == null,
    var.network.keycloak_security_group_ids == null,
    var.network.kafka_security_group_ids == null,
    var.network.instance_profile_name == null,
  ])

  net = try(data.terraform_remote_state.network[0].outputs, {})

  subnet_id = (
    var.network.subnet_id != null
    ? var.network.subnet_id
    : try(local.net.public_subnet_ids[var.network.subnet_key], null)
  )

  keycloak_security_group_ids = (
    var.network.keycloak_security_group_ids != null
    ? var.network.keycloak_security_group_ids
    : try([local.net.security_group_ids[var.network.keycloak_security_group_key]], null)
  )

  kafka_security_group_ids = (
    var.network.kafka_security_group_ids != null
    ? var.network.kafka_security_group_ids
    : try([local.net.security_group_ids[var.network.kafka_security_group_key]], null)
  )

  instance_profile_name = (
    var.network.instance_profile_name != null
    ? var.network.instance_profile_name
    : try(local.net.instance_profile_names[var.network.instance_profile_key], null)
  )

  ami_id = var.ami_id != null ? var.ami_id : try(data.aws_ssm_parameter.ami[0].value, null)

  keycloak_admin_password = (
    var.keycloak.admin_password != null
    ? var.keycloak.admin_password
    : try(random_password.keycloak_admin[0].result, null)
  )

  kafka_ui_password = (
    var.kafka.ui_password != null
    ? var.kafka.ui_password
    : try(random_password.kafka_ui_user[0].result, null)
  )

  kafka_ui_client_secret = random_password.kafka_ui_client_secret.result
}
