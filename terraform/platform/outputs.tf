# Cluster name used by kubectl and Helm on the bastion.
output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

# Private API endpoint (reachable only from inside the VPC).
output "cluster_endpoint" {
  description = "Private API endpoint of the cluster."
  value       = module.eks.cluster_endpoint
}

# Bastion instance ID for `aws ssm start-session --target` (null when the bastion is off).
output "bastion_instance_id" {
  description = "Instance ID of the bastion, or null."
  value       = try(module.bastion[0].instance_id, null)
}

# Role ARN for the AWS Load Balancer Controller service account annotation.
output "lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller."
  value       = module.irsa_lb_controller.role_arn
}

# Role ARN for the vLLM service account annotation.
output "vllm_role_arn" {
  description = "IRSA role ARN for the vLLM service account."
  value       = module.irsa_vllm.role_arn
}

# VPC and subnet details the Kubernetes manifests need (for the LB controller flags).
output "vpc_id" {
  description = "ID of the VPC."
  value       = local.foundation.vpc_id
}

# ECR repository URLs for Helm values and manifests (from the foundation stack).
output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by image name."
  value       = local.foundation.ecr_repository_urls
}
