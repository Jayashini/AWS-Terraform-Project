variable "bucket_name" {
  description = "Globally unique name for the private S3 bucket"
  type        = string

  validation {
    condition     = length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 && can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters, use lowercase letters, numbers, dots, or hyphens, and start and end with a letter or number."
  }
}

variable "purpose" {
  description = "Purpose recorded in the bucket tags"
  type        = string
}
