variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name; used in tags and in the bucket name prefix."
  type        = string
  default     = "private-llm"
}

variable "environment" {
  description = "Environment name (also used as part of the state key path)."
  type        = string
  default     = "sandbox"
}

variable "owner" {
  description = "Owner tag value. Set via TF_VAR_owner or an untracked tfvars file; do not commit personal details."
  type        = string
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old state versions before expiry."
  type        = number
  default     = 90
}
