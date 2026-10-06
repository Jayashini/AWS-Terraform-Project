variable "project_name" {
  description = "Project name used to tag the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the web server"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Private subnet ID for the web server"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the web server"
  type        = string
}
