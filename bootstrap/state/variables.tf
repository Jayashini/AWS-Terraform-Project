variable "aws_region" {
  description = "AWS region for the Terraform state bucket"
  type        = string
  default     = "ap-southeast-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the private Terraform state bucket"
  type        = string

  validation {
    condition     = length(var.state_bucket_name) >= 3 && length(var.state_bucket_name) <= 63 && can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be 3-63 characters, use lowercase letters, numbers, dots, or hyphens, and start and end with a letter or number."
  }
}
