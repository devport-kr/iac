variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for NLB"
  type        = string
}

variable "ec2_instance_id" {
  description = "EC2 instance ID to register with target group"
  type        = string
}

variable "certificate_arn" {
  description = "Regional ACM certificate ARN for the TLS listener"
  type        = string
}

variable "enable_http_listener" {
  description = "Enable HTTP listener (port 80) for redirects"
  type        = bool
  default     = false
}
