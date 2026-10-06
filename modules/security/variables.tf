variable "project_name" {
  description = "Project name used to tag security groups"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which to create the security groups"
  type        = string
}
