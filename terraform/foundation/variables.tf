variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name; used in tags and names."
  type        = string
  default     = "private-llm"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "assessment"
}

variable "owner" {
  description = "Owner tag value. No personal details (no emails or names of individuals)."
  type        = string
  default     = "platform"
}

variable "vpc_cidr" {
  description = "CIDR of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Two Availability Zones for the private subnets (EKS and the internal ALB need two)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "One private subnet CIDR per AZ, same order as azs."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "primary_az" {
  description = "The single working AZ where nodes, bastion and endpoints are placed (ADR-008). Must be one of azs."
  type        = string
  default     = "us-east-1a"

  validation {
    condition     = contains(var.azs, var.primary_az)
    error_message = "primary_az must be one of azs."
  }
}

variable "ecr_repositories" {
  description = "Private ECR repositories for mirrored images (no NAT, so every image must be pulled from here)."
  type        = list(string)
  default = [
    "vllm",
    "nvidia-device-plugin",
    "dcgm-exporter",
    "aws-load-balancer-controller",
    "prometheus",
    "alertmanager",
    "prometheus-operator",
    "prometheus-config-reloader",
    "grafana",
    "kube-state-metrics",
    "node-exporter",
    "loki",
    "promtail",
    "busybox",
    "loadtest",
  ]
}
