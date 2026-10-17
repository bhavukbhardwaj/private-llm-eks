# Repository URLs keyed by name, used when mirroring images and in Kubernetes manifests.
output "repository_urls" {
  description = "ECR repository URLs keyed by repository name."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

# Repository ARNs keyed by name, used in IAM policies.
output "repository_arns" {
  description = "ECR repository ARNs keyed by repository name."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
