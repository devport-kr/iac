variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "iprof_key" {
  description = "S3 object key for the canonical PGO profile consumed by CI"
  type        = string
  default     = "pgo/default.iprof"
}
