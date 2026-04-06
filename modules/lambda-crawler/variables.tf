#------------------------------------------------------------------------------
# General
#------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "api_domain" {
  description = "API domain name"
  type        = string
}

#------------------------------------------------------------------------------
# Lambda Configuration
#------------------------------------------------------------------------------
variable "schedule_expression" {
  description = "EventBridge schedule expression (applied to all crawler sources)"
  type        = string
  default     = "cron(0 15 * * ? *)" # daily at midnight KST (UTC+9)
}

variable "timeout" {
  description = "Lambda timeout in seconds (max 900)"
  type        = number
  default     = 900
}

variable "crawler_tiers" {
  description = "Map of Lambda tier names to their memory and source configuration"
  type = map(object({
    memory_size = number
    sources     = list(string)
  }))
}

variable "enable_function_url" {
  description = "Enable Lambda function URL for manual invocation"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# VPC Configuration
#------------------------------------------------------------------------------
variable "subnet_ids" {
  description = "List of subnet IDs for Lambda VPC configuration"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for Lambda VPC configuration"
  type        = list(string)
}

#------------------------------------------------------------------------------
# Database Connection
#------------------------------------------------------------------------------
variable "db_host" {
  description = "PostgreSQL host (EC2 private IP)"
  type        = string
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

#------------------------------------------------------------------------------
# API Keys (sensitive)
#------------------------------------------------------------------------------
variable "openai_api_key" {
  description = "OpenAI API key for LLM summarization"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_token" {
  description = "GitHub API token for rate limits and project data"
  type        = string
  default     = ""
  sensitive   = true
}

variable "artificial_analysis_api_key" {
  description = "Artificial Analysis API key for LLM rankings"
  type        = string
  default     = ""
  sensitive   = true
}

#------------------------------------------------------------------------------
# Optional Webhooks
#------------------------------------------------------------------------------
variable "discord_webhook_url" {
  description = "Discord webhook URL for failed content fetch notifications"
  type        = string
  default     = ""
}

variable "crawler_webhook_url" {
  description = "Webhook URL for crawler completion signals"
  type        = string
  default     = ""
}

variable "crawler_webhook_secret" {
  description = "HMAC secret for crawler webhook signing"
  type        = string
  default     = ""
  sensitive   = true
}

#------------------------------------------------------------------------------
# Extra Environment Variables
#------------------------------------------------------------------------------
variable "extra_env_vars" {
  description = "Additional environment variables to pass to the Lambda (overrides defaults)"
  type        = map(string)
  default     = {}
}
