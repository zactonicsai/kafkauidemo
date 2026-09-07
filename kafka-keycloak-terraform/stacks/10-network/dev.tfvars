###############################################################################
# NETWORK STACK - dev values
# Run: terraform -chdir=stacks/10-network apply -var-file=dev.tfvars
###############################################################################

aws_region   = "us-east-1"
project_name = "kafka-keycloak-lab"

tags = {
  Environment = "dev"
}

# Leave null to auto-pick the first AZ that supports every listed type.
availability_zone               = null
instance_types_for_az_selection = ["t3.medium", "t3.small"]

vpc_cidr = "10.40.0.0/16"

public_subnets = {
  public-a = {
    cidr_block = "10.40.1.0/24"
  }
  # Add more as needed; AZ defaults to the selected AZ unless set here.
  # public-b = { cidr_block = "10.40.2.0/24", availability_zone = "us-east-1b" }
}

private_subnets    = {}
create_nat_gateway = false

# Recommended: your public IPv4 address /32 (example only; do not use 203.0.113.10 literally).
# allowed_cidr = "203.0.113.10/32"
allowed_cidr = "0.0.0.0/0"

###############################################################################
# Security groups. "ALLOWED_CIDR" is replaced by var.allowed_cidr.
# Egress defaults to allow-all when omitted.
###############################################################################

security_groups = {
  kafka = {
    description = "Kafka and Kafka UI EC2 access"
    ingress = [
      {
        description = "Kafka UI from allowed client network"
        from_port   = 8080
        to_port     = 8080
        cidr_ipv4   = "ALLOWED_CIDR"
      }
    ]
  }

  keycloak = {
    description = "Keycloak EC2 access"
    ingress = [
      {
        description = "Keycloak HTTPS browser/admin access"
        from_port   = 8443
        to_port     = 8443
        cidr_ipv4   = "ALLOWED_CIDR"
      },
      {
        description               = "Kafka UI private OIDC HTTPS back-channel"
        from_port                 = 8443
        to_port                   = 8443
        source_security_group_key = "kafka"
      },
      {
        description = "Keycloak health and metrics from allowed client network"
        from_port   = 9000
        to_port     = 9000
        cidr_ipv4   = "ALLOWED_CIDR"
      }
    ]
  }
}

###############################################################################
# IAM instance roles / profiles
###############################################################################

instance_roles = {
  ec2_ssm = {
    description         = "SSM Session Manager access for lab EC2 hosts"
    managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  }
}
