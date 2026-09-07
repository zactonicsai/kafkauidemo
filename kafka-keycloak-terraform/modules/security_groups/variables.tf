variable "name" {
  description = "Name prefix for security groups."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "security_groups" {
  description = <<-EOT
    Map of security groups keyed by short name. Each rule must set exactly one
    source: cidr_ipv4, cidr_ipv6, source_security_group_key (another key in this
    map), source_security_group_id (an existing SG outside this map) or self.
    Use protocol = "-1" for all traffic (ports are then ignored).
  EOT
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

  validation {
    condition = alltrue(flatten([
      for sg in var.security_groups : [
        for r in concat(sg.ingress, sg.egress) :
        length([for v in [r.cidr_ipv4, r.cidr_ipv6, r.source_security_group_key, r.source_security_group_id, r.self ? "self" : null] : v if v != null]) == 1
      ]
    ]))
    error_message = "Every security group rule must set exactly one of cidr_ipv4, cidr_ipv6, source_security_group_key, source_security_group_id or self."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
