# Role ARN to put in the service account annotation eks.amazonaws.com/role-arn.
output "role_arn" {
  description = "ARN of the IAM role."
  value       = aws_iam_role.this.arn
}
