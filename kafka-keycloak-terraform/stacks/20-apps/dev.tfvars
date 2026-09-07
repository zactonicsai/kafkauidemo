###############################################################################
# APPS STACK - dev values
# Run after the network stack:
#   terraform -chdir=stacks/20-apps apply -var-file=dev.tfvars
###############################################################################

aws_region   = "us-east-1"
project_name = "kafka-keycloak-lab"

tags = {
  Environment = "dev"
}

# Where to read the network stack outputs. Match stacks/10-network backend.
network_state = {
  backend = "local"
  config = {
    path = "../10-network/terraform.tfstate"
  }
}
# S3 example:
# network_state = {
#   backend = "s3"
#   config = {
#     bucket = "my-tf-state"
#     key    = "kafka-keycloak/network.tfstate"
#     region = "us-east-1"
#   }
# }

# Keys into the network stack outputs. Uncomment *_id fields to bypass
# remote state and target an existing VPC instead.
network = {
  subnet_key                  = "public-a"
  keycloak_security_group_key = "keycloak"
  kafka_security_group_key    = "kafka"
  instance_profile_key        = "ec2_ssm"

  # subnet_id                   = "subnet-0123456789abcdef0"
  # keycloak_security_group_ids = ["sg-0123456789abcdef0"]
  # kafka_security_group_ids    = ["sg-0123456789abcdef1"]
  # instance_profile_name       = "my-existing-profile"
}

# AMI: null resolves the latest Amazon Linux 2023 via SSM.
ami_id            = null
ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

keycloak = {
  enabled          = true
  instance_type    = "t3.small"
  root_volume_size = 20
  admin_username   = "admin"
  # admin_password = "set-to-override-the-generated-one"
}

# Kafka + Kafka UI need more memory than Keycloak alone.
kafka = {
  enabled          = true
  instance_type    = "t3.medium"
  root_volume_size = 30
  ui_username      = "kafkauser"
  # ui_password    = "set-to-override-the-generated-one"
}
