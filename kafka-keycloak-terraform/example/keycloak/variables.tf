# ---------------------------------------------------------------------------
# Infrastructure (all private)
# ---------------------------------------------------------------------------
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "keycloak"
}

variable "instance_subnet_id" {
  description = "Private subnet for the Keycloak instance."
  type        = string
}

variable "lb_subnet_ids" {
  description = "Private subnets for the internal ALB (at least two, in different AZs, same VPC as instance_subnet_id)."
  type        = list(string)

  validation {
    condition     = length(var.lb_subnet_ids) >= 2
    error_message = "An ALB requires at least two subnets in different availability zones."
  }
}

variable "allowed_cidr_blocks" {
  description = "Private CIDRs allowed to reach the internal ALB."
  type        = list(string)
  default     = ["10.0.0.0/8"]

  validation {
    condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "This example is private-only; 0.0.0.0/0 is not allowed."
  }
}

variable "image_id" {
  type    = string
  default = null
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "key_name" {
  type    = string
  default = null
}

variable "additional_security_group_ids" {
  type    = list(string)
  default = []
}

variable "root_volume_size" {
  type    = number
  default = 30
}

variable "create_instance" {
  description = "Launch one instance from the template and register it with the target group."
  type        = bool
  default     = true
}

variable "termination_protection" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------
variable "certificate_arn" {
  description = "ACM certificate for an HTTPS (443) listener. When null the listener is plain HTTP on 80."
  type        = string
  default     = null
}

variable "ssl_policy" {
  type    = string
  default = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "lb_idle_timeout" {
  type    = number
  default = 60
}

# ---------------------------------------------------------------------------
# Keycloak
# ---------------------------------------------------------------------------
variable "keycloak_image" {
  description = "Docker image reference for Keycloak."
  type        = string
  default     = "quay.io/keycloak/keycloak:26.3"
}

variable "keycloak_hostname" {
  description = "Public-facing hostname users reach Keycloak on (the DNS name pointing at the ALB). Sets KC_HOSTNAME."
  type        = string
}

variable "keycloak_http_port" {
  description = "Host port mapped to the container's 8080 and used by the target group."
  type        = number
  default     = 8080
}

variable "keycloak_management_port" {
  description = "Host port mapped to the container's 9000 (health/metrics)."
  type        = number
  default     = 9000
}

variable "keycloak_env" {
  description = <<-EOT
    KC_* environment variables passed to the container. Merged on top of the
    example's defaults (proxy headers, hostname, health/metrics, DB when set);
    caller values win. See https://www.keycloak.org/server/all-config.
  EOT
  type        = map(string)
  default     = {}
}

variable "keycloak_user_properties" {
  description = <<-EOT
    Extra key/value entries written to conf/keycloak.conf inside the container
    (e.g. spi-* provider settings, cache options). Useful for options that are
    awkward as environment variables.
  EOT
  type        = map(string)
  default     = {}
}

variable "keycloak_extra_args" {
  description = "Additional arguments appended to `kc.sh start` (e.g. [\"--features=token-exchange\"])."
  type        = list(string)
  default     = []
}

variable "keycloak_admin_username" {
  type    = string
  default = "admin"
}

variable "keycloak_admin_password" {
  type      = string
  sensitive = true

  validation {
    condition     = length(var.keycloak_admin_password) >= 12
    error_message = "keycloak_admin_password must be at least 12 characters."
  }
}

# ---------------------------------------------------------------------------
# Database (optional – omit for the embedded dev-file store)
# ---------------------------------------------------------------------------
variable "db_vendor" {
  type    = string
  default = "postgres"
}

variable "db_url" {
  description = "JDBC URL, e.g. jdbc:postgresql://host:5432/keycloak. Null uses the embedded dev-file database (NOT for production)."
  type        = string
  default     = null
}

variable "db_username" {
  type    = string
  default = "keycloak"
}

variable "db_password" {
  type      = string
  default   = ""
  sensitive = true
}
