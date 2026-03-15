#------------------------------------------------------------------------------
# DevPort Production Environment
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"
}

module "devport" {
  source = "../../"

  # General
  project_name = "devport"
  environment  = "prod"
  aws_region   = "ap-northeast-2"

  # Domain
  domain_name         = var.domain_name
  api_subdomain       = "api"
  create_route53_zone = var.create_route53_zone
  route53_zone_id     = var.route53_zone_id

  # VPC
  vpc_cidr            = "10.1.0.0/16"  # Different CIDR from dev
  public_subnet_cidr  = "10.1.1.0/24"
  private_subnet_cidr = "10.1.2.0/24"
  availability_zone   = "ap-northeast-2a"

  # EC2 - production size
  instance_type    = "t4g.small"
  create_key_pair  = true
  ec2_volume_size  = 30  # Larger for prod
  ec2_volume_type  = "gp3"

  # Database
  db_name     = "devport_db"
  db_user     = "devport"
  db_password = var.db_password

  # SSL (Let's Encrypt via certbot DNS-01 on EC2)
  certbot_email = var.certbot_email

  # Lambda Crawler
  crawler_schedule    = "rate(6 hours)"  # As specified in architecture
  crawler_timeout     = 300
  crawler_memory_size = 512  # More memory for prod

  # CloudFront
  cloudfront_price_class    = "PriceClass_200"  # Better coverage for prod
  enable_cloudfront_logging = true

  # Backups
  enable_backup_bucket  = true
  backup_retention_days = 7  # Week of backups

  # Monitoring
  enable_cloudwatch_alarms = true
  alarm_email              = var.alarm_email
  cpu_alarm_threshold      = 80
}

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------
variable "domain_name" {
  description = "Primary domain name"
  type        = string
}

variable "create_route53_zone" {
  description = "Create new Route 53 hosted zone"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Existing Route 53 hosted zone ID"
  type        = string
  default     = ""
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

variable "alarm_email" {
  description = "Email for CloudWatch alarms"
  type        = string
}

variable "certbot_email" {
  description = "Email for Let's Encrypt certificate registration"
  type        = string
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------
output "frontend_url" {
  value = module.devport.frontend_url
}

output "api_url" {
  value = module.devport.api_url
}

output "ec2_instance_id" {
  value = module.devport.ec2_instance_id
}

output "ec2_private_ip" {
  value = module.devport.ec2_private_ip
}

output "frontend_bucket_name" {
  value = module.devport.frontend_bucket_name
}

output "cloudfront_distribution_id" {
  value = module.devport.cloudfront_distribution_id
}

output "crawler_function_name" {
  value = module.devport.crawler_function_name
}

output "ssm_connect_command" {
  value = "aws ssm start-session --target ${module.devport.ec2_instance_id}"
}

output "deployment_info" {
  value = module.devport.deployment_info
}
