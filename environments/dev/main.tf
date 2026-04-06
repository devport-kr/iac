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
  instance_type   = "t4g.micro" # Smaller for dev
  create_key_pair = true
  ec2_volume_size = 20
  ec2_volume_type = "gp3"

  # Database
  db_name     = "devport_db"
  db_user     = "devport"
  db_password = var.db_password

  # Lambda Crawler
  crawler_schedule = "cron(0 15 * * ? *)" # daily at midnight KST
  crawler_timeout  = 900

  # Crawler API keys
  crawler_openai_api_key              = var.crawler_openai_api_key
  crawler_github_token                = var.crawler_github_token
  crawler_artificial_analysis_api_key = var.crawler_artificial_analysis_api_key

  # Crawler webhooks
  crawler_discord_webhook_url = var.crawler_discord_webhook_url
  crawler_webhook_url         = var.crawler_webhook_url
  crawler_webhook_secret      = var.crawler_webhook_secret
  crawler_extra_env_vars      = var.crawler_extra_env_vars
  crawler_github_repo         = var.crawler_github_repo

  # CloudFront
  cloudfront_price_class    = "PriceClass_100" # Cheapest for dev
  enable_cloudfront_logging = false

  # Backups
  enable_backup_bucket  = true
  backup_retention_days = 3 # Shorter retention for dev

  # Monitoring
  enable_cloudwatch_alarms = false # Disabled for dev
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

variable "crawler_openai_api_key" {
  description = "OpenAI API key for crawler"
  type        = string
  default     = ""
  sensitive   = true
}

variable "crawler_github_token" {
  description = "GitHub API token for crawler"
  type        = string
  default     = ""
  sensitive   = true
}

variable "crawler_artificial_analysis_api_key" {
  description = "Artificial Analysis API key for crawler"
  type        = string
  default     = ""
  sensitive   = true
}

variable "crawler_discord_webhook_url" {
  description = "Discord webhook URL for crawler notifications"
  type        = string
  default     = ""
}

variable "crawler_webhook_url" {
  description = "Webhook URL for crawler completion signals"
  type        = string
  default     = ""
}

variable "crawler_webhook_secret" {
  description = "HMAC secret for crawler webhook"
  type        = string
  default     = ""
  sensitive   = true
}

variable "crawler_extra_env_vars" {
  description = "Additional environment variables for crawler"
  type        = map(string)
  default     = {}
}

variable "crawler_github_repo" {
  description = "GitHub repo for crawler CI/CD OIDC"
  type        = string
  default     = "devport-kr/devport-crawler"
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

output "crawler_function_names" {
  value = module.devport.crawler_function_names
}

output "crawler_ecr_repository_url" {
  value = module.devport.crawler_ecr_repository_url
}

output "github_actions_crawler_role_arn" {
  value = module.devport.github_actions_crawler_role_arn
}

output "ssm_connect_command" {
  value = "aws ssm start-session --target ${module.devport.ec2_instance_id}"
}

output "deployment_info" {
  value = module.devport.deployment_info
}
