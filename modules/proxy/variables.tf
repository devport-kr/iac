variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for proxy"
  type        = string
  default     = "t4g.nano"
}

variable "ami_id" {
  description = "AMI ID (empty for latest Amazon Linux 2023 ARM)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Public subnet ID for proxy instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for proxy instance"
  type        = string
}

variable "api_domain" {
  description = "API domain name (e.g., api.devport.kr)"
  type        = string
}

variable "backend_ip" {
  description = "Private IP of the backend EC2 instance"
  type        = string
}

variable "certbot_email" {
  description = "Email address for Let's Encrypt certificate registration"
  type        = string
}
