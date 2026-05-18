output "instance_id" {
  description = "ID de la instancia EC2"
  value       = aws_instance.app_server.id
}

output "public_ip" {
  description = "IP pública de la instancia EC2"
  value       = aws_instance.app_server.public_ip
}

output "public_dns" {
  description = "DNS público de la instancia EC2"
  value       = aws_instance.app_server.public_dns
}

output "ssh_command" {
  description = "Comando SSH para conectarte a la instancia"
  value       = "ssh -i ~/.ssh/rideglory-key.pem ec2-user@${aws_instance.app_server.public_ip}"
}

output "api_url" {
  description = "URL base de la API"
  value       = "http://${aws_instance.app_server.public_ip}:3000/api"
}