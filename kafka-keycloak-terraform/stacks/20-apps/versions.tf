terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # backend "s3" {
  #   bucket         = "my-tf-state"
  #   key            = "kafka-keycloak/apps.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "my-tf-locks"
  #   encrypt        = true
  # }
}
