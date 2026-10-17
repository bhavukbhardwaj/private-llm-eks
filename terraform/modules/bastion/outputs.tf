# Instance ID used in `aws ssm start-session --target`.
output "instance_id" {
  description = "ID of the bastion instance."
  value       = aws_instance.this.id
}

# Role ARN, mapped to cluster admin through an EKS access entry.
output "role_arn" {
  description = "ARN of the bastion IAM role."
  value       = aws_iam_role.this.arn
}

# Security group ID, allowed to reach the EKS API on 443.
output "security_group_id" {
  description = "ID of the bastion security group."
  value       = aws_security_group.this.id
}
