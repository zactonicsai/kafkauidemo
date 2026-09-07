###############################################################################
# NETWORK STACK (process 1)
#
# VPC, subnets, security groups and IAM instance roles. Run this first; the
# apps stack consumes its outputs by remote state or by explicit IDs.
###############################################################################

###############################################################################
# Pick an AZ that supports every instance type the apps stack will use.
###############################################################################

data "aws_ec2_instance_type_offerings" "by_type" {
  for_each = var.availability_zone == null ? toset(var.instance_types_for_az_selection) : toset([])

  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [each.value]
  }
}

locals {
  az_sets = [for k, d in data.aws_ec2_instance_type_offerings.by_type : toset(d.locations)]

  common_azs = length(local.az_sets) == 0 ? [] : sort(tolist(setintersection(local.az_sets...)))

  selected_availability_zone = coalesce(var.availability_zone, try(local.common_azs[0], null))

  # Allow tfvars to write cidr_ipv4 = "ALLOWED_CIDR" instead of repeating the CIDR.
  security_groups = {
    for k, sg in var.security_groups : k => merge(sg, {
      ingress = [for r in sg.ingress : merge(r, { cidr_ipv4 = r.cidr_ipv4 == "ALLOWED_CIDR" ? var.allowed_cidr : r.cidr_ipv4 })]
      egress  = [for r in sg.egress : merge(r, { cidr_ipv4 = r.cidr_ipv4 == "ALLOWED_CIDR" ? var.allowed_cidr : r.cidr_ipv4 })]
    })
  }
}

check "availability_zone_available" {
  assert {
    condition     = local.selected_availability_zone != null
    error_message = "No Availability Zone in ${var.aws_region} supports all of: ${join(", ", var.instance_types_for_az_selection)}. Set availability_zone explicitly or change instance types."
  }
}

###############################################################################
# VPC
###############################################################################

module "vpc" {
  source = "../../modules/vpc"

  name                      = var.project_name
  cidr_block                = var.vpc_cidr
  default_availability_zone = local.selected_availability_zone
  public_subnets            = var.public_subnets
  private_subnets           = var.private_subnets
  create_nat_gateway        = var.create_nat_gateway
  tags                      = var.tags
}

###############################################################################
# SECURITY GROUPS
###############################################################################

module "security_groups" {
  source = "../../modules/security_groups"

  name            = var.project_name
  vpc_id          = module.vpc.vpc_id
  security_groups = local.security_groups
  tags            = var.tags
}

###############################################################################
# IAM INSTANCE ROLES
###############################################################################

module "instance_roles" {
  source   = "../../modules/iam_instance_role"
  for_each = var.instance_roles

  name                = "${var.project_name}-${each.key}"
  description         = each.value.description
  managed_policy_arns = each.value.managed_policy_arns
  inline_policies     = each.value.inline_policies
  tags                = var.tags
}
