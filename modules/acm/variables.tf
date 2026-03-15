variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "domain_name" {
  description = "Primary domain name for certificate"
  type        = string
}

variable "api_domain" {
  description = "API origin domain name for the regional certificate"
  type        = string
}

variable "create_www_cert" {
  description = "Include www subdomain in certificate"
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for DNS validation"
  type        = string
}
