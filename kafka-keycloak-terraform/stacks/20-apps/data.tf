###############################################################################
# NETWORK STACK OUTPUTS + AMI
###############################################################################

data "terraform_remote_state" "network" {
  count = local.needs_remote_state ? 1 : 0

  backend = var.network_state.backend
  config  = var.network_state.config
}

data "aws_ssm_parameter" "ami" {
  count = var.ami_id == null ? 1 : 0
  name  = var.ami_ssm_parameter
}
