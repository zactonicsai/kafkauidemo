variable "project" { type = string }
variable "domain_name" { type = string }
variable "certificate_hosts" {
  description = "All hostnames the certificate must cover, e.g. [keycloak.example.com, kafka.example.com]"
  type        = list(string)
}
