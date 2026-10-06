variable "project_name" {
  description = "Project name used to tag VPC resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "Two availability zones for the subnets"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two availability zones must be provided."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly two public subnet CIDR blocks must be provided."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Exactly two private subnet CIDR blocks must be provided."
  }
}
