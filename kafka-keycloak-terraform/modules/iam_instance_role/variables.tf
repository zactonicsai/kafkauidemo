variable "name" {
  description = "Name prefix for the role and instance profile."
  type        = string
}

variable "description" {
  type    = string
  default = "EC2 instance role"
}

variable "managed_policy_arns" {
  description = "AWS managed (or customer managed) policy ARNs to attach."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

variable "inline_policies" {
  description = "Map of inline policy name => JSON policy document."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
