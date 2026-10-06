output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.alb.dns_name
}

output "web_url" {
  description = "Web application URL"
  value       = "http://${module.alb.dns_name}"
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = module.ec2.instance_id
}
