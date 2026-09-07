variable "instance_type" {
  description = "t3.medium (4 GB) minimum for Kafka + Kafka UI"
  type        = string
  default     = "t3.medium"
}
variable "root_volume_gb" {
  type    = number
  default = 30
}
