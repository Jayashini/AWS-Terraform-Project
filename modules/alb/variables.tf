variable "project_name" {
  description = "Project name used to name and tag ALB resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the target group"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the load balancer"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least two public subnet IDs must be provided."
  }
}

variable "security_group_id" {
  description = "Security group ID for the load balancer"
  type        = string
}

variable "target_instance_id" {
  description = "EC2 instance ID to register with the target group"
  type        = string
}
