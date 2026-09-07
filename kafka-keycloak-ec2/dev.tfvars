# Copy this file to terraform.tfvars and edit it.

aws_region    = "us-east-1"
project_name  = "kafka-keycloak-lab"
instance_type = "t3.medium"

# SAFER:
# Replace this example with your real public IPv4 address followed by /32.
# Example only; do not use 203.0.113.10 literally.
allowed_cidr = "10.0.1.0/24"

# EASY LAB OPTION, BUT PUBLIC TO THE INTERNET:
# allowed_cidr = "0.0.0.0/0"

kafka_ui_username       = "kafkauser"
keycloak_admin_username = "admin"
