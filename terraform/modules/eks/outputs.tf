# Cluster name for kubeconfig and add-ons.
output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

# Private API endpoint URL.
output "cluster_endpoint" {
  description = "Private API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

# Cluster security group, used by nodes and by the ALB target rules.
output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# OIDC provider ARN for IRSA trust policies.
output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider."
  value       = aws_iam_openid_connect_provider.this.arn
}

# OIDC issuer without https://, as used in IRSA conditions.
output "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix."
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

# Node role ARN, for reference.
output "node_role_arn" {
  description = "ARN of the worker node IAM role."
  value       = aws_iam_role.node.arn
}

# Lets callers wait until the system nodes exist before creating add-ons that need them.
output "system_node_group_id" {
  description = "ID of the system node group."
  value       = aws_eks_node_group.system.id
}
