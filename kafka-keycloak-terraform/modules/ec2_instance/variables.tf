variable "name" {
  type = string
}

variable "launch_template_id" {
  type = string
}

variable "launch_template_version" {
  description = "Launch template version; pass tostring(module.lt.latest_version) or \"$Latest\"."
  type        = string
  default     = "$Latest"
}

variable "eip_allocation_id" {
  description = "Optional Elastic IP allocation id to associate."
  type        = string
  default     = null
}

variable "termination_protection" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
