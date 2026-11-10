terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "10-foundation/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Layer     = "10-foundation"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront 에 붙이는 ACM 인증서는 반드시 us-east-1 에서 발급해야 한다.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project
      Layer     = "10-foundation"
      ManagedBy = "terraform"
    }
  }
}
