#------------------------------------------------------------------------------
# General Configuration
#------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "devport"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-2"
}

#------------------------------------------------------------------------------
# Domain Configuration
#------------------------------------------------------------------------------
variable "domain_name" {
  description = "Primary domain name (e.g., devport.kr)"
  type        = string
}

variable "api_subdomain" {
  description = "Subdomain for API (e.g., api)"
  type        = string
  default     = "api"
}

variable "create_route53_zone" {
  description = "Whether to create a new Route 53 hosted zone or use existing"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Existing Route 53 hosted zone ID (required if create_route53_zone is false)"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# VPC Configuration
#------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the subnet"
  type        = string
  default     = "ap-northeast-2a"
}

#------------------------------------------------------------------------------
# EC2 Configuration
#------------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.small"
}

variable "ec2_ami_id" {
  description = "AMI ID for EC2 instance (leave empty for latest Amazon Linux 2023 ARM)"
  type        = string
  default     = ""
}

variable "ec2_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "ec2_volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

#------------------------------------------------------------------------------
# Database Configuration
#------------------------------------------------------------------------------
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "devport_db"
}

variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "devport"
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

#------------------------------------------------------------------------------
# Lambda Crawler Configuration
#------------------------------------------------------------------------------
variable "crawler_schedule" {
  description = "EventBridge schedule expression for crawler (e.g., rate(6 hours))"
  type        = string
  default     = "rate(6 hours)"
}

variable "crawler_timeout" {
  description = "Lambda crawler timeout in seconds"
  type        = number
  default     = 300
}

variable "crawler_memory_size" {
  description = "Lambda crawler memory size in MB"
  type        = number
  default     = 256
}

variable "psycopg2_layer_arn" {
  description = "ARN of psycopg2 Lambda layer for PostgreSQL access"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# S3 & CloudFront Configuration
#------------------------------------------------------------------------------
variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_100, PriceClass_200, PriceClass_All)"
  type        = string
  default     = "PriceClass_200"
}

variable "enable_cloudfront_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Backup Configuration
#------------------------------------------------------------------------------
variable "backup_retention_days" {
  description = "Number of days to retain database backups in S3"
  type        = number
  default     = 7
}

variable "enable_backup_bucket" {
  description = "Create S3 bucket for backups"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Monitoring Configuration
#------------------------------------------------------------------------------
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for EC2"
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for alarm (percentage)"
  type        = number
  default     = 80
}

#------------------------------------------------------------------------------
# SSL Certificate Configuration
#------------------------------------------------------------------------------
variable "certbot_email" {
  description = "Email address for Let's Encrypt (certbot) certificate registration for api subdomain"
  type        = string
}
