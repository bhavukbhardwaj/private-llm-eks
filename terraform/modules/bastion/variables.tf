variable "name" {
  description = "Name prefix for the bastion resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the bastion."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR; the bastion may only open HTTPS connections inside it."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet (working AZ) for the bastion."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster the bastion administers (used by the kubeconfig helper)."
  type        = string
}

variable "tools_bucket_arn" {
  description = "ARN of the S3 bucket holding kubectl, helm and manifests."
  type        = string
}

variable "tools_bucket" {
  description = "Name of the tools bucket."
  type        = string
}

variable "instance_type" {
  description = "Bastion instance type (Arm, ADR-001)."
  type        = string
  default     = "t4g.micro"
}

variable "root_volume_gb" {
  description = "Root volume size in GB (gp3, ADR-003)."
  type        = number
  default     = 10
}
