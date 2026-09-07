variable "name" {
  description = "Name prefix for the launch template and tagged resources."
  type        = string
}

variable "description" {
  type    = string
  default = null
}

variable "image_id" {
  description = "AMI id."
  type        = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  description = "Optional EC2 key pair name. SSM Session Manager is the preferred access path."
  type        = string
  default     = null
}

variable "iam_instance_profile_name" {
  type    = string
  default = null
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "associate_public_ip_address" {
  type    = bool
  default = true
}

variable "user_data" {
  description = "Plain-text user data. The module base64-encodes it."
  type        = string
  default     = null
  sensitive   = true
}

variable "update_default_version" {
  type    = bool
  default = true
}

variable "ebs_optimized" {
  type    = bool
  default = true
}

variable "root_device_name" {
  type    = string
  default = "/dev/xvda"
}

variable "root_volume_type" {
  type    = string
  default = "gp3"
}

variable "root_volume_size" {
  type    = number
  default = 20
}

variable "root_volume_iops" {
  type    = number
  default = null
}

variable "root_volume_throughput" {
  type    = number
  default = null
}

variable "root_volume_encrypted" {
  type    = bool
  default = true
}

variable "root_volume_kms_key_id" {
  type    = string
  default = null
}

variable "additional_volumes" {
  type = list(object({
    device_name           = string
    volume_type           = optional(string, "gp3")
    volume_size           = number
    encrypted             = optional(bool, true)
    delete_on_termination = optional(bool, true)
  }))
  default = []
}

variable "require_imdsv2" {
  type    = bool
  default = true
}

variable "metadata_hop_limit" {
  description = "Set to 2 when containers on the host need IMDS access."
  type        = number
  default     = 1
}

variable "enable_instance_metadata_tags" {
  type    = bool
  default = false
}

variable "detailed_monitoring" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "instance_tags" {
  type    = map(string)
  default = {}
}

variable "volume_tags" {
  type    = map(string)
  default = {}
}
