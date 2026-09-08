# ---------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource in this example."
  type        = string
  default     = "nifi"
}

variable "subnet_id" {
  description = "Subnet the NiFi instance launches into."
  type        = string
}

variable "image_id" {
  description = "AMI id. Defaults to the latest Amazon Linux 2023 x86_64 image via SSM."
  type        = string
  default     = null
}

variable "instance_type" {
  type    = string
  default = "m6i.large"
}

variable "key_name" {
  description = "Optional EC2 key pair. SSM Session Manager is enabled regardless."
  type        = string
  default     = null
}

variable "enable_ssh" {
  description = "Open port 22 to allowed_cidr_blocks."
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDRs allowed to reach the NiFi UI (and SSH when enabled)."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "additional_security_group_ids" {
  type    = list(string)
  default = []
}

variable "associate_public_ip_address" {
  type    = bool
  default = false
}

variable "root_volume_size" {
  type    = number
  default = 30
}

variable "data_volume_device" {
  description = "Device name for a dedicated repository volume. Empty string disables it and repositories live on the root volume."
  type        = string
  default     = "/dev/xvdb"
}

variable "data_volume_size" {
  type    = number
  default = 100
}

variable "data_volume_mount" {
  type    = string
  default = "/data/nifi"
}

variable "create_instance" {
  description = "Also launch one instance from the template using the ec2_instance module."
  type        = bool
  default     = true
}

variable "eip_allocation_id" {
  type    = string
  default = null
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
# NiFi installation
# ---------------------------------------------------------------------------
variable "nifi_version" {
  type    = string
  default = "2.4.0"
}

variable "nifi_download_url" {
  description = "Override the NiFi distribution URL (e.g. an internal mirror or S3 presigned URL)."
  type        = string
  default     = null
}

variable "java_version" {
  description = "Amazon Corretto major version. NiFi 2.x requires 21."
  type        = string
  default     = "21"
}

# ---------------------------------------------------------------------------
# NiFi configuration
# ---------------------------------------------------------------------------
variable "nifi_properties" {
  description = <<-EOT
    Key/value overrides applied to conf/nifi.properties at boot. Existing keys are
    replaced in place; unknown keys are appended. Takes precedence over the
    example's built-in defaults (https host/port, proxy host, repository paths).
  EOT
  type        = map(string)
  default     = {}
}

variable "nifi_user_properties" {
  description = <<-EOT
    Custom user-defined properties written to conf/<nifi_user_properties_file>
    and registered through nifi.variable.registry.properties so they are
    available to processors as expression-language variables.
  EOT
  type        = map(string)
  default     = {}
}

variable "nifi_user_properties_file" {
  type    = string
  default = "custom.properties"
}

variable "nifi_proxy_host" {
  description = "Value for nifi.web.proxy.host (host[:port] list) when the UI sits behind a load balancer or DNS name."
  type        = string
  default     = ""
}

variable "nifi_sensitive_props_key" {
  description = "Key used to encrypt sensitive processor properties in the flow. Must be at least 12 characters."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.nifi_sensitive_props_key) >= 12
    error_message = "nifi_sensitive_props_key must be at least 12 characters."
  }
}

variable "nifi_single_user_username" {
  description = "Single-user login. Set to empty string to keep NiFi's auto-generated credentials (printed in nifi-app.log)."
  type        = string
  default     = "admin"
}

variable "nifi_single_user_password" {
  description = "Single-user password (NiFi requires >= 12 characters)."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.nifi_single_user_password == "" || length(var.nifi_single_user_password) >= 12
    error_message = "nifi_single_user_password must be empty or at least 12 characters."
  }
}
