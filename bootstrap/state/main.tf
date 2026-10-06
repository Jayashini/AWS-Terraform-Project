terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "s3" {
  source = "../../modules/s3"

  bucket_name = var.state_bucket_name
  purpose     = "Terraform state"
}
