###############################################################################
# GENERAL
###############################################################################

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used on all resources."
  type        = string
  default     = "kafka-keycloak-lab"
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}

###############################################################################
# AVAILABILITY ZONE SELECTION
#
# Either pin `availability_zone`, or list the instance types the apps stack
# will launch and this stack picks the first AZ that offers all of them.
###############################################################################

variable "availability_zone" {
  description = "Explicit AZ for subnets that do not set their own. Leave null to auto-select."
  type        = string
  default     = null
}

variable "instance_types_for_az_selection" {
  description = "Instance types that the selected AZ must support (used only when availability_zone is null)."
  type        = list(string)
  default     = ["t3.medium", "t3.small"]
}

###############################################################################
# VPC + SUBNETS
###############################################################################

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "public_subnets" {
  description = "Public subnets keyed by short name. availability_zone falls back to the selected AZ."
  type = map(object({
    cidr_block              = string
    availability_zone       = optional(string)
    map_public_ip_on_launch = optional(bool, true)
    tags                    = optional(map(string), {})
  }))
  default = {
    public-a = { cidr_block = "10.40.1.0/24" }
  }
}

variable "private_subnets" {
  description = "Optional private subnets keyed by short name."
  type = map(object({
    cidr_block        = string
    availability_zone = optional(string)
    tags              = optional(map(string), {})
  }))
  default = {}
}

variable "create_nat_gateway" {
  type    = bool
  default = false
}

###############################################################################
# SECURITY GROUPS
#
# Fully data-driven; see dev.tfvars for the Kafka / Keycloak rule set.
###############################################################################

variable "allowed_cidr" {
  description = "Convenience value referenced by dev.tfvars via `allowed_cidr` placeholders. YOUR_PUBLIC_IP/32 recommended."
  type        = string
  default     = "0.0.0.0/0"
}

variable "security_groups" {
  description = "Security groups to create. Rules may use cidr_ipv4 = \"ALLOWED_CIDR\" to substitute var.allowed_cidr."
  type = map(object({
    description = string
    tags        = optional(map(string), {})
    ingress = optional(list(object({
      description               = optional(string)
      from_port                 = optional(number)
      to_port                   = optional(number)
      protocol                  = optional(string, "tcp")
      cidr_ipv4                 = optional(string)
      cidr_ipv6                 = optional(string)
      source_security_group_key = optional(string)
      source_security_group_id  = optional(string)
      self                      = optional(bool, false)
    })), [])
    egress = optional(list(object({
      description               = optional(string)
      from_port                 = optional(number)
      to_port                   = optional(number)
      protocol                  = optional(string, "-1")
      cidr_ipv4                 = optional(string)
      cidr_ipv6                 = optional(string)
      source_security_group_key = optional(string)
      source_security_group_id  = optional(string)
      self                      = optional(bool, false)
    })), [{ description = "Allow all outbound", protocol = "-1", cidr_ipv4 = "0.0.0.0/0" }])
  }))
  default = {}
}

###############################################################################
# IAM INSTANCE ROLES
###############################################################################

variable "instance_roles" {
  description = "Instance roles / profiles keyed by short name."
  type = map(object({
    description         = optional(string, "EC2 instance role")
    managed_policy_arns = optional(list(string), ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"])
    inline_policies     = optional(map(string), {})
  }))
  default = {
    ec2_ssm = {}
  }
}
