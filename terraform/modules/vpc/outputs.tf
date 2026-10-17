# VPC ID for security groups, endpoints and EKS.
output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

# VPC CIDR, used in security group rules.
output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

# Map of AZ name to private subnet ID, so stacks can pick the working AZ.
output "private_subnet_ids_by_az" {
  description = "Private subnet IDs keyed by Availability Zone."
  value       = { for i, az in var.azs : az => aws_subnet.private[i].id }
}

# Private route table, needed to attach more gateway endpoints later.
output "private_route_table_id" {
  description = "ID of the private route table."
  value       = aws_route_table.private.id
}

# S3 gateway endpoint ID, for reference.
output "s3_endpoint_id" {
  description = "ID of the S3 gateway VPC endpoint."
  value       = aws_vpc_endpoint.s3.id
}
