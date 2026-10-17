# Security group for the endpoints: only HTTPS (443) from inside the VPC is allowed in.
resource "aws_security_group" "endpoints" {
  count = length(var.services) > 0 ? 1 : 0

  name_prefix = "${var.name}-vpce-"
  description = "Allow HTTPS from the VPC to interface endpoints"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-vpce" }

  lifecycle {
    create_before_destroy = true
  }
}

# The only ingress rule: TCP 443 from the VPC CIDR (nodes and pods reach AWS APIs here).
resource "aws_vpc_security_group_ingress_rule" "https" {
  count = length(var.services) > 0 ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

# One interface endpoint per service with private DNS, so SDKs use the endpoint with no code change.
resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.name}-${each.value}" }
}
