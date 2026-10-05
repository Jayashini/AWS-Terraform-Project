variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "terraform-aws-project"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ami_id" {
  description = "Amazon Linux 2023 x86_64 AMI ID in the configured AWS region"
  type        = string

  validation {
    condition     = can(regex("^ami-([0-9a-f]{8}|[0-9a-f]{17})$", var.ami_id))
    error_message = "ami_id must be a valid-format AMI ID (ami- followed by 8 or 17 lowercase hexadecimal characters)."
  }
}