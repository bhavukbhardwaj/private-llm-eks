# VPC ID, read by the platform stack.
output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

# VPC CIDR, read by the platform stack for security group rules.
output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr
}

# All private subnet IDs keyed by AZ (EKS needs both).
output "private_subnet_ids_by_az" {
  description = "Private subnet IDs keyed by Availability Zone."
  value       = module.vpc.private_subnet_ids_by_az
}

# The working AZ and its subnet, where nodes, bastion and endpoints go.
output "primary_az" {
  description = "The single working Availability Zone."
  value       = var.primary_az
}

# Subnet in the working AZ.
output "primary_subnet_id" {
  description = "Private subnet ID in the working AZ."
  value       = module.vpc.private_subnet_ids_by_az[var.primary_az]
}

# Route table that the gateway and interface endpoints attach to.
output "private_route_table_id" {
  description = "ID of the private route table."
  value       = module.vpc.private_route_table_id
}

# Model weights bucket name.
output "models_bucket" {
  description = "Name of the model weights bucket."
  value       = module.models_bucket.bucket_id
}

# Model weights bucket ARN, for the IRSA policy.
output "models_bucket_arn" {
  description = "ARN of the model weights bucket."
  value       = module.models_bucket.bucket_arn
}

# Tools bucket name.
output "tools_bucket" {
  description = "Name of the tools bucket."
  value       = module.tools_bucket.bucket_id
}

# Tools bucket ARN, for the bastion role.
output "tools_bucket_arn" {
  description = "ARN of the tools bucket."
  value       = module.tools_bucket.bucket_arn
}

# ECR repository URLs keyed by name, for mirroring and manifests.
output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by name."
  value       = module.ecr.repository_urls
}

# ECR repository ARNs keyed by name, for IAM policies.
output "ecr_repository_arns" {
  description = "ECR repository ARNs keyed by name."
  value       = module.ecr.repository_arns
}
