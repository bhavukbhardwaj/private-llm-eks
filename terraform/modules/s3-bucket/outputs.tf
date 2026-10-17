# Bucket name, used in IAM policies and sync commands.
output "bucket_id" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.id
}

# Bucket ARN, used in IAM policies.
output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}
