terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    key = "60-edge/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Layer     = "60-edge"
      ManagedBy = "terraform"
    }
  }
}
