#------------------------------------------------------------------------------
# Networking Outputs
#------------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.networking.public_subnet_id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.networking.private_subnet_id
}

output "nat_instance_id" {
  description = "ID of the NAT instance"
  value       = module.networking.nat_instance_id
}

#------------------------------------------------------------------------------
# EC2 Outputs
#------------------------------------------------------------------------------
output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.ec2.instance_id
}

output "ec2_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = module.ec2.instance_private_ip
}

output "ssm_connect_command" {
  description = "SSM Session Manager command to connect to EC2 instance"
  value       = "aws ssm start-session --target ${module.ec2.instance_id}"
}

#------------------------------------------------------------------------------
# S3 & CloudFront Outputs
#------------------------------------------------------------------------------
output "frontend_bucket_name" {
  description = "Name of the frontend S3 bucket"
  value       = module.s3_cloudfront.frontend_bucket_id
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = module.s3_cloudfront.cloudfront_distribution_id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = module.s3_cloudfront.cloudfront_domain_name
}

output "backup_bucket_name" {
  description = "Name of the backup S3 bucket"
  value       = module.s3_cloudfront.backup_bucket_name
}

#------------------------------------------------------------------------------
# Proxy Outputs
#------------------------------------------------------------------------------
output "proxy_instance_id" {
  description = "ID of the proxy EC2 instance"
  value       = module.proxy.instance_id
}

output "proxy_elastic_ip" {
  description = "Elastic IP of the public proxy"
  value       = module.proxy.elastic_ip
}

#------------------------------------------------------------------------------
# Lambda Crawler Outputs
#------------------------------------------------------------------------------
output "crawler_function_name" {
  description = "Name of the crawler Lambda function"
  value       = module.lambda_crawler.function_name
}

output "crawler_function_arn" {
  description = "ARN of the crawler Lambda function"
  value       = module.lambda_crawler.function_arn
}

#------------------------------------------------------------------------------
# Route 53 Outputs
#------------------------------------------------------------------------------
output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions frontend deployment"
  value       = aws_iam_role.github_actions_frontend.arn
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = local.route53_zone_id
}

output "route53_name_servers" {
  description = "Name servers for the hosted zone (if created)"
  value       = var.create_route53_zone ? aws_route53_zone.main[0].name_servers : []
}

#------------------------------------------------------------------------------
# URLs
#------------------------------------------------------------------------------
output "frontend_url" {
  description = "Frontend URL"
  value       = "https://${var.domain_name}"
}

output "api_url" {
  description = "API URL"
  value       = "https://${local.api_domain}"
}

#------------------------------------------------------------------------------
# Deployment Information
#------------------------------------------------------------------------------
output "deployment_info" {
  description = "Deployment information and next steps"
  value       = <<-EOT

    ============================================
    DevPort Infrastructure Deployed Successfully
    ============================================

    Frontend URL: https://${var.domain_name}
    API URL: https://${local.api_domain}

    EC2 Instance ID: ${module.ec2.instance_id}
    EC2 Private IP: ${module.ec2.instance_private_ip}

    Connect via SSM: aws ssm start-session --target ${module.ec2.instance_id}

    Proxy Instance ID: ${module.proxy.instance_id}
    Proxy Elastic IP: ${module.proxy.elastic_ip}

    NEXT STEPS:
    -----------
    1. Connect to app EC2 via SSM Session Manager:
       aws ssm start-session --target ${module.ec2.instance_id}

    2. Deploy your docker-compose.yml to /opt/devport/:
       cd /opt/devport
       sudo cp .env.template .env
       sudo vim .env  # Set POSTGRES_PASSWORD and other secrets
       docker-compose up -d

    3. Connect to proxy EC2 via SSM:
       aws ssm start-session --target ${module.proxy.instance_id}

    4. Deploy frontend:
       aws s3 sync ./build s3://${module.s3_cloudfront.frontend_bucket_id}
       aws cloudfront create-invalidation --distribution-id ${module.s3_cloudfront.cloudfront_distribution_id} --paths "/*"

    5. Test the crawler:
       aws lambda invoke --function-name ${module.lambda_crawler.function_name} response.json
       cat response.json

  EOT
}
