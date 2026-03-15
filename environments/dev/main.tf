#------------------------------------------------------------------------------
# DevPort Development Environment
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"
}

module "devport" {
  source = "../../"

  # General
  project_name = "devport"
  environment  = "dev"
  aws_region   = "ap-northeast-2"

  # Domain
  domain_name         = var.domain_name
  api_subdomain       = "api"
  create_route53_zone = var.create_route53_zone
  route53_zone_id     = var.route53_zone_id

  # VPC
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  availability_zone   = "ap-northeast-2a"

  # EC2 - smaller instance for dev
  instance_type    = "t4g.micro"  # Smaller for dev
  create_key_pair  = true
  ec2_volume_size  = 20
  ec2_volume_type  = "gp3"

  # Database
  db_name     = "devport_db"
  db_user     = "devport"
  db_password = var.db_password

  # Lambda Crawler
  crawler_schedule    = "rate(12 hours)"  # Less frequent for dev
  crawler_timeout     = 300
  crawler_memory_size = 256

  # CloudFront
  cloudfront_price_class    = "PriceClass_100"  # Cheapest for dev
  enable_cloudfront_logging = false

  # Backups
  enable_backup_bucket  = true
  backup_retention_days = 3  # Shorter retention for dev

  # Monitoring
  enable_cloudwatch_alarms = false  # Disabled for dev
  alarm_email              = ""
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
