output "instance_id" {
  description = "ID of the web server instance"
  value       = aws_instance.web.id
}
