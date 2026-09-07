###############################################################################
# SECURITY GROUPS BASE MODULE
#
# Accepts a map of security groups, each with a list of ingress and egress
# rules. Rules may reference another security group in the same map by key
# (source_security_group_key), which lets tfvars express "Kafka UI may reach
# Keycloak" without hard-coding IDs. Groups are created first and rules are
# attached afterwards, so cross-references never form a cycle.
###############################################################################

resource "aws_security_group" "this" {
  for_each = var.security_groups

  name_prefix = "${var.name}-${each.key}-"
  description = each.value.description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, each.value.tags, { Name = "${var.name}-${each.key}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  ingress_rules = flatten([
    for sg_key, sg in var.security_groups : [
      for idx, rule in sg.ingress : {
        id                        = "${sg_key}-ingress-${idx}"
        sg_key                    = sg_key
        description               = rule.description
        from_port                 = rule.from_port
        to_port                   = rule.to_port
        protocol                  = rule.protocol
        cidr_ipv4                 = rule.cidr_ipv4
        cidr_ipv6                 = rule.cidr_ipv6
        source_security_group_key = rule.source_security_group_key
        source_security_group_id  = rule.source_security_group_id
        self                      = rule.self
      }
    ]
  ])

  egress_rules = flatten([
    for sg_key, sg in var.security_groups : [
      for idx, rule in sg.egress : {
        id                        = "${sg_key}-egress-${idx}"
        sg_key                    = sg_key
        description               = rule.description
        from_port                 = rule.from_port
        to_port                   = rule.to_port
        protocol                  = rule.protocol
        cidr_ipv4                 = rule.cidr_ipv4
        cidr_ipv6                 = rule.cidr_ipv6
        source_security_group_key = rule.source_security_group_key
        source_security_group_id  = rule.source_security_group_id
        self                      = rule.self
      }
    ]
  ])
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = { for r in local.ingress_rules : r.id => r }

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port

  cidr_ipv4 = each.value.cidr_ipv4
  cidr_ipv6 = each.value.cidr_ipv6
  referenced_security_group_id = (
    each.value.self ? aws_security_group.this[each.value.sg_key].id :
    each.value.source_security_group_key != null ? aws_security_group.this[each.value.source_security_group_key].id :
    each.value.source_security_group_id
  )

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = { for r in local.egress_rules : r.id => r }

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port

  cidr_ipv4 = each.value.cidr_ipv4
  cidr_ipv6 = each.value.cidr_ipv6
  referenced_security_group_id = (
    each.value.self ? aws_security_group.this[each.value.sg_key].id :
    each.value.source_security_group_key != null ? aws_security_group.this[each.value.source_security_group_key].id :
    each.value.source_security_group_id
  )

  tags = merge(var.tags, { Name = each.key })
}
