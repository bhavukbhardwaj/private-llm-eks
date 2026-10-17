variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "versioning" {
  description = "Keep object versions (recommended for model weights so a bad upload can be rolled back)."
  type        = bool
  default     = true
}

variable "noncurrent_version_retention_days" {
  description = "Days before old object versions expire (only used when versioning is on)."
  type        = number
  default     = 30
}

variable "force_destroy" {
  description = "Allow destroying a non-empty bucket (sandbox teardown only)."
  type        = bool
  default     = false
}
