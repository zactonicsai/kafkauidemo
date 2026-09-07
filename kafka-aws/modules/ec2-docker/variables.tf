variable "project" { type = string }
variable "name" {
  description = "Short role name, e.g. keycloak or kafka"
  type        = string
}
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "alb_security_group_id" { type = string }
variable "ingress_ports" { type = list(number) }
variable "instance_type" { type = string }
variable "root_volume_gb" {
  type    = number
  default = 20
}
variable "app_script" {
  description = "Bash appended to cloud-init after Docker is installed"
  type        = string
}
variable "extra_policy_arns" {
  type    = list(string)
  default = []
}
