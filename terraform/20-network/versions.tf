terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "20-network/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Layer     = "20-network"
      ManagedBy = "terraform"
    }
  }
}
