###############################################################################
# GENERAL
###############################################################################

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used on all resources. Should match the network stack."
  type        = string
  default     = "kafka-keycloak-lab"
}

variable "tags" {
  type    = map(string)
  default = {}
}

###############################################################################
# NETWORK INPUTS
#
# Option A (default): read the network stack's remote state and look resources
# up by key. Option B: pass IDs directly (vpc_id, subnet_id, ...) which take
# precedence and let this stack run against any pre-existing network.
###############################################################################

variable "network_state" {
  description = "Backend used to read the network stack's state. Set backend = \"s3\" and config accordingly for shared state."
  type = object({
    backend = string
    config  = map(string)
  })
  default = {
    backend = "local"
    config = {
      path = "../10-network/terraform.tfstate"
    }
  }
}

variable "network" {
  description = "Keys used to look up resources in the network stack outputs. Any *_id set here overrides the lookup."
  type = object({
    subnet_key                  = optional(string, "public-a")
    keycloak_security_group_key = optional(string, "keycloak")
    kafka_security_group_key    = optional(string, "kafka")
    instance_profile_key        = optional(string, "ec2_ssm")

    # Direct overrides (Option B)
    vpc_id                      = optional(string)
    subnet_id                   = optional(string)
    keycloak_security_group_ids = optional(list(string))
    kafka_security_group_ids    = optional(list(string))
    instance_profile_name       = optional(string)
  })
  default = {}
}

###############################################################################
# AMI
###############################################################################

variable "ami_id" {
  description = "Explicit AMI id. Leave null to resolve ami_ssm_parameter."
  type        = string
  default     = null
}

variable "ami_ssm_parameter" {
  description = "SSM public parameter for the AMI (default: latest Amazon Linux 2023 x86_64)."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

###############################################################################
# KEYCLOAK
###############################################################################

variable "keycloak" {
  description = "Keycloak EC2 settings."
  type = object({
    enabled          = optional(bool, true)
    instance_type    = optional(string, "t3.small")
    root_volume_size = optional(number, 20)
    root_volume_type = optional(string, "gp3")
    key_name         = optional(string)
    admin_username   = optional(string, "admin")
    admin_password   = optional(string) # null => generated
    tags             = optional(map(string), {})
  })
  default = {}
}

###############################################################################
# KAFKA + KAFKA UI
###############################################################################

variable "kafka" {
  description = "Kafka + Kafka UI EC2 settings."
  type = object({
    enabled          = optional(bool, true)
    instance_type    = optional(string, "t3.medium")
    root_volume_size = optional(number, 30)
    root_volume_type = optional(string, "gp3")
    key_name         = optional(string)
    ui_username      = optional(string, "kafkauser")
    ui_password      = optional(string) # null => generated
    tags             = optional(map(string), {})
  })
  default = {}
}
