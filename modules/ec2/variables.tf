variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.small"
}

variable "ami_id" {
  description = "AMI ID (empty for latest Amazon Linux 2023 ARM)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for EC2 instance"
  type        = string
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

variable "domain_name" {
  description = "Primary domain name"
  type        = string
}

variable "api_domain" {
  description = "API domain name"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
}

variable "certbot_email" {
  description = "Email address for Let's Encrypt (certbot) certificate registration"
  type        = string
}

variable "enable_backup" {
  description = "Enable S3 backup policy"
  type        = bool
  default     = false
}

variable "backup_bucket_arn" {
  description = "ARN of S3 bucket for backups"
  type        = string
  default     = ""
}

variable "backup_bucket_name" {
  description = "Name of S3 bucket for backups"
  type        = string
  default     = ""
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for alarm"
  type        = number
  default     = 80
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
  default     = ""
}
