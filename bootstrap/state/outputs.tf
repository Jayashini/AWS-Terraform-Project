output "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state"
  value       = module.s3.bucket_name
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket used for Terraform state"
  value       = module.s3.bucket_arn
}
