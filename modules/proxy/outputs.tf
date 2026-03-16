output "instance_id" {
  description = "ID of the proxy EC2 instance"
  value       = aws_instance.proxy.id
}

output "elastic_ip" {
  description = "Elastic IP address of the proxy"
  value       = aws_eip.proxy.public_ip
}
