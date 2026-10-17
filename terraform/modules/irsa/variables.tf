variable "name" {
  description = "IAM role name."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider."
  type        = string
}

variable "oidc_provider_url" {
  description = "Issuer URL of the OIDC provider without the https:// prefix."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account."
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account name allowed to assume the role."
  type        = string
}

variable "policy_json" {
  description = "Inline IAM policy document (JSON). Leave null if only managed policies are used."
  type        = string
  default     = null
}

variable "managed_policy_arns" {
  description = "AWS managed policy ARNs to attach."
  type        = list(string)
  default     = []
}
