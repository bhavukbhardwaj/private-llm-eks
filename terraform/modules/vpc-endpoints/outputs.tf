# Endpoint IDs keyed by service, for reference and debugging.
output "endpoint_ids" {
  description = "Interface endpoint IDs keyed by service short name."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

# Endpoint security group ID (null when no endpoints are created).
output "security_group_id" {
  description = "ID of the endpoint security group, or null."
  value       = try(aws_security_group.endpoints[0].id, null)
}
