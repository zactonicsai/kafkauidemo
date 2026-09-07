variable "instance_type" {
  description = "t3.small (2 GB) is enough for Keycloak alone"
  type        = string
  default     = "t3.small"
}
variable "keycloak_admin_password" {
  type      = string
  sensitive = true
}
variable "keycloak_client_secret" {
  description = "OIDC client secret for the kafka-ui client (long random string)"
  type        = string
  sensitive   = true
}
variable "alice_password" {
  type      = string
  sensitive = true
}
variable "bob_password" {
  type      = string
  sensitive = true
}
