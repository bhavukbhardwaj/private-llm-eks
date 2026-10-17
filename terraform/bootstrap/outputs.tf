# Bucket name, needed by the other stacks' backend config.
output "state_bucket" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.state.id
}

# Ready-to-run `terraform init` flags for the foundation stack.
output "backend_config_foundation" {
  description = "Arguments for `terraform init` in the foundation stack."
  value       = <<-EOT
    terraform init \
      -backend-config="bucket=${aws_s3_bucket.state.id}" \
      -backend-config="key=${var.project}/${var.environment}/foundation/terraform.tfstate" \
      -backend-config="region=${var.region}" \
      -backend-config="use_lockfile=true" \
      -backend-config="encrypt=true"
  EOT
}

# Ready-to-run `terraform init` flags for the platform stack.
output "backend_config_platform" {
  description = "Arguments for `terraform init` in the platform stack."
  value       = <<-EOT
    terraform init \
      -backend-config="bucket=${aws_s3_bucket.state.id}" \
      -backend-config="key=${var.project}/${var.environment}/platform/terraform.tfstate" \
      -backend-config="region=${var.region}" \
      -backend-config="use_lockfile=true" \
      -backend-config="encrypt=true"
  EOT
}
