terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Uncomment and fill in for team use. The apps stack reads this stack's
  # outputs via terraform_remote_state, so keep the backend settings in sync
  # with stacks/20-apps `network_state`.
  # backend "s3" {
  #   bucket         = "my-tf-state"
  #   key            = "kafka-keycloak/network.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "my-tf-locks"
  #   encrypt        = true
  # }
}
