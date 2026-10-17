# Latest Amazon Linux 2023 Arm image, read from the public SSM parameter.
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# S3 managed prefix list, so the bastion can reach S3 through the gateway endpoint and nothing else outside the VPC.
data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

# Trust policy letting EC2 assume the bastion role.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Role for the bastion instance; it has no access beyond what is attached below.
resource "aws_iam_role" "this" {
  name               = "${var.name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Lets Session Manager manage the instance (browser or CLI shell, no SSH, no inbound ports).
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Read-only access to the tools bucket and cluster discovery, nothing else.
data "aws_iam_policy_document" "bastion" {
  statement {
    sid       = "ReadTools"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.tools_bucket_arn, "${var.tools_bucket_arn}/*"]
  }

  statement {
    sid       = "DescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

# Attaches the least-privilege bastion permissions.
resource "aws_iam_role_policy" "bastion" {
  name   = "${var.name}-bastion"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.bastion.json
}

# Instance profile that connects the role to the EC2 instance.
resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-bastion"
  role = aws_iam_role.this.name
}

# Security group with no inbound rules; outbound only HTTPS to the VPC and to S3.
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-bastion-"
  description = "Bastion: no inbound, HTTPS out to VPC and S3 only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-bastion" }

  lifecycle {
    create_before_destroy = true
  }
}

# Egress to VPC endpoints and the EKS API endpoint inside the VPC.
resource "aws_vpc_security_group_egress_rule" "vpc" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to VPC (endpoints, EKS API, ALB)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

# Egress to S3 through the gateway endpoint (package repos and the tools bucket).
resource "aws_vpc_security_group_egress_rule" "s3" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to S3 via gateway endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_prefix_list.s3.id
}

# Egress to the internal ALB on port 80 for the in-VPC curl test.
resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.this.id
  description       = "HTTP to the internal ALB inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.vpc_cidr
}

# The bastion: Spot t4g.micro, persistent request that stops (not terminates) on interruption, no public IP, no detailed monitoring.
resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false
  monitoring                  = false

  instance_market_options {
    market_type = "spot"

    spot_options {
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  # First boot: copy kubectl/helm from the tools bucket and add a helper that writes the kubeconfig.
  user_data = <<-EOT
    #!/bin/bash
    set -eu
    mkdir -p /usr/local/bin
    aws s3 sync "s3://${var.tools_bucket}/bin/" /usr/local/bin/ --region ${var.region} || true
    chmod +x /usr/local/bin/* || true
    cat > /usr/local/bin/kube-setup <<'SCRIPT'
    #!/bin/bash
    aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}
    SCRIPT
    chmod +x /usr/local/bin/kube-setup
    echo 'export AWS_REGION=${var.region} AWS_DEFAULT_REGION=${var.region}' > /etc/profile.d/aws-region.sh
  EOT

  tags = { Name = "${var.name}-bastion" }

  lifecycle {
    ignore_changes = [ami]
  }
}
