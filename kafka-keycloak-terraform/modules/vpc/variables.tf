variable "name" {
  description = "Name prefix applied to every resource in this module."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
}

variable "enable_dns_support" {
  type    = bool
  default = true
}

variable "enable_dns_hostnames" {
  type    = bool
  default = true
}

variable "create_internet_gateway" {
  description = "Create an Internet Gateway and a default route for public subnets."
  type        = bool
  default     = true
}

variable "default_availability_zone" {
  description = "AZ used for any subnet that does not set its own availability_zone."
  type        = string
  default     = null
}

variable "public_subnets" {
  description = "Map of public subnets keyed by a short name (e.g. public-a)."
  type = map(object({
    cidr_block              = string
    availability_zone       = optional(string)
    map_public_ip_on_launch = optional(bool, true)
    tags                    = optional(map(string), {})
  }))
  default = {}
}

variable "private_subnets" {
  description = "Map of private subnets keyed by a short name (e.g. private-a)."
  type = map(object({
    cidr_block        = string
    availability_zone = optional(string)
    tags              = optional(map(string), {})
  }))
  default = {}
}

variable "create_nat_gateway" {
  description = "Create one NAT Gateway (in the first public subnet) for private subnet egress."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
