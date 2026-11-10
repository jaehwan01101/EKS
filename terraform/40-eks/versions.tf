terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "40-eks/terraform.tfstate" # 20-network 에서 바뀐 곳 1: state 파일 경로
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Layer     = "40-eks" # 20-network 에서 바뀐 곳 2: 레이어 태그
      ManagedBy = "terraform"
    }
  }
}