# ADR-004: Security (SSO, KMS key, private access, audit logging)

- **Status:** Accepted (2026-10-18)

## Context
- The brief asks for no public ingress, no NAT, encryption at rest, IRSA, and no long-lived or committed credentials.
- Personal account, one operator. Checked: root MFA on, no root keys, 0 IAM users, account-wide S3 Block Public Access on.
- The account already has one customer-managed KMS key (made by Identity Center). Its policy lets the account root delegate access.
- EKS control-plane logs can only go to CloudWatch (about $0.50/GB).

## Decision
**Access: SSO, no keys**
- IAM Identity Center with MFA, 8-hour sessions. No access keys for people. Pods use IRSA.
- Account IDs are never hard-coded. Temporary credentials live only in environment variables, never in the repo.

**Encryption: reuse the existing KMS key**
- Node EBS volumes use it (`encrypted = true`, `kms_key_id`). Terraform only references the ARN (`kms_key_arn`, in the untracked tfvars). It never creates or destroys the key. One `aws_kms_grant` lets the Auto Scaling role use it.
- Not on the key: S3 (SSE-S3), EKS secrets (EKS default), ECR (AES256), bastion volume (`aws/ebs`).

**Cluster access: private API, SSM bastion**
- EKS API endpoint is private only. The bastion (Spot `t4g.micro`) has no public IP, no inbound rules and no SSH key. People reach it through Session Manager.
- The bastion's role is cluster admin through an EKS access entry. Its security group allows egress only to the VPC (443) and S3.
- No internet on the bastion: kubectl, helm and manifests come from the S3 tools bucket.
- Grafana is viewed through an SSM port-forward, never exposed.

**Audit logging**
- No CloudTrail trail (Event History keeps 90 days). EKS logs (`api`, `audit`, `authenticator`) are off by default and switch on with `enable_eks_control_plane_logs`. No VPC flow logs, no Container Insights.
- Pod logs, if needed, go through Loki and Promtail, not CloudWatch.

## Alternatives considered
- **IAM user access keys:** long-lived and easy to leak.
- **New KMS key:** about $1/month more and one more key to delete. **AWS-managed key only:** misses the brief's customer-managed key line.
- **Public API endpoint limited to my IP:** free, but a public control-plane address.
- **CloudTrail trail:** better retention, but a bucket and cleanup for one user.
- **EKS logs always on:** meets the brief, but adds CloudWatch cost.

## Consequences
**Positive**
- Short-lived MFA credentials; nothing to leak or commit.
- Customer-managed key requirement met at no extra cost; nothing left behind after destroy.
- Nothing is reachable from the internet.

**Negative**
- The KMS key is shared with Identity Center, and rotation is off.
- `AdministratorAccess` is broader than least privilege.
- Credentials expired several times and needed a fresh login each time.
- **Deviations from the brief:** no EKS audit logs by default, no `logs` VPC endpoint, no CloudTrail trail. Production needs all three, with dedicated keys in a separate account (see the law-firm answer).
