# ADR-004: Security (SSO, encryption, private access, audit logging)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-003](ADR-003-cost-and-sizing.md), [docs/security.md](../security.md), [task.md](../../task.md) section 2.2
- **Index:** D1 SSO, D2 existing KMS key, D3 private API and SSM bastion, D4 audit logging and CloudTrail

## Context
- Personal AWS account, one operator, no organisation guardrails.
- The brief assesses security: no public ingress, no NAT for model traffic, encryption at rest, IRSA, no long-lived or committed credentials.
- Hardening checked 2026-10-18: root MFA on, no root keys, 0 IAM users, account-wide S3 Block Public Access on.
- Account already has one customer-managed KMS key (created by Identity Center). Its policy gives the account root `kms:*`. EBS default encryption is off.
- EKS control-plane logs can only go to CloudWatch Logs (about $0.50/GB ingested).

## Decision
**D1 SSO, not access keys**
- IAM Identity Center with MFA and an 8-hour session. `aws configure sso`, `aws sso login`, `AWS_PROFILE`.
- No AK/SK for people. Exceptions need a new ADR and an expiry. Pods use IRSA only.
- Account ID comes from `data.aws_caller_identity`, never hard-coded.
- Pasted temporary credentials are used as environment variables only, never saved in the repo.

**D2 Reuse the existing customer-managed KMS key for node EBS**
- Terraform only references it by ARN (`kms_key_arn`). It never creates, edits or destroys it.
- The ARN contains the account ID, so it lives in the untracked `terraform.tfvars`.
- Used for system and GPU node root volumes (`encrypted = true`, `kms_key_id`).
- One extra resource: an `aws_kms_grant` for the Auto Scaling service-linked role (it exists).
- Not used for S3 (SSE-S3), EKS secrets (EKS default), ECR (AES256) or the bastion volume (`aws/ebs`).
- Bastion volume stays on `aws/ebs` because a persistent Spot request needs another grant, for the EC2 Spot service-linked role, which does not exist yet.
- `kms_key_arn = null` falls back to AWS-managed encryption.
- The `kms` endpoint stays in the list (the brief names it). EBS does not use it, so it is an idle $0.01/hr.

**D3 Private EKS API, reached through an SSM bastion**
- API endpoint is private only.
- Bastion: `t4g.micro` Spot, private subnet, no public IP, no inbound rules, no SSH key.
- Persistent Spot request with behaviour `stop`: it restarts and keeps its disk. On-Demand is an unused fallback (about $0.0084/hr).
- Session Manager from the EC2 console or the CLI. IAM: `AmazonSSMManagedInstanceCore` plus an EKS access entry with cluster admin.
- Network: SG may reach the API on 443. Egress limited to the VPC and S3.
- Endpoints `ssm`, `ssmmessages`, `ec2messages` in one AZ, only for working sessions.
- No internet on the bastion: kubectl, helm and manifests come from the S3 tools bucket.
- Terraform (AWS resources) runs from the laptop; Helm and kubectl run on the bastion.
- The demo `curl` runs from the bastion and from a client pod.
- **Viewing Grafana** (nothing public):
  - Bastion: `kubectl -n monitoring port-forward svc/grafana 3000:80 --address 127.0.0.1`
  - Laptop: `aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'`
  - Open `http://localhost:3000`. Admin password comes from the cluster secret.
  - Needs `session-manager-plugin` on the laptop (install needs `sudo`).

**D4 Audit logging: no CloudTrail trail, EKS logs off by default**
- No CloudTrail trail. Use Event History (90 days, free).
- `enable_eks_control_plane_logs = false`. When on: types `["api", "audit", "authenticator"]`, retention `eks_log_retention_days = 3`.
- With the toggle off, no log types are enabled and **no log group is created**. Turning it on needs the owner's approval.
- No VPC flow logs, Container Insights, CloudWatch agent, session logging or alarms.
- No `logs` VPC endpoint by default (it would cost $0.01/hr for nothing).
- Operational logs: Loki + Promtail (or Alloy) in Grafana, on node disk or S3. Loki cannot replace the EKS audit log.

## Alternatives considered
- **D1 IAM user with AK/SK:** long-lived, on disk, easy to leak. **Root credentials:** unauditable. **Assume-role from an IAM user:** still needs a long-lived key.
- **D1 Least-privilege policy instead of Administrator:** better for production, too slow to tune in 3 days.
- **D2 New dedicated CMK:** own policy and rotation, but about $1/month more, one more key to delete (7 to 30 day window).
- **D2 AWS-managed `aws/ebs` only:** free, but misses the brief's CMK line.
- **D2 Edit the Identity Center key policy:** risks breaking SSO; the grant needs no edit.
- **D3 Public endpoint limited to my IP /32:** free and simple, but a public control-plane address. Documented fallback.
- **D3 Public-subnet bastion with SSH:** internet-facing host plus key pair. **Client VPN or Direct Connect:** about $70+/month. **Open endpoint 0.0.0.0/0:** not acceptable.
- **D3 Internal ALB for Grafana:** about $0.03/hr more for no gain.
- **D4 CloudTrail trail to S3:** better retention, but a bucket, policy and cleanup for one user.
- **D4 EKS logs always on:** meets the brief, but adds CloudWatch cost for no PoC benefit.
- **D4 Ship control-plane logs elsewhere:** not possible; EKS delivers them only to CloudWatch.

## Consequences
**Positive**
- Short-lived MFA credentials; nothing long-lived to leak or commit.
- CMK requirement met at $0 extra; nothing created, nothing left after destroy.
- Nothing reachable from the internet: no inbound ports, no SSH keys, IAM-authenticated sessions.
- $0 CloudWatch spend by default; audit logging is one variable away.
- Cleanup is removing one SSO assignment.

**Negative**
- Credentials expired three times in the first 10 hours, each needing a fresh login.
- `AdministratorAccess` is broader than least privilege.
- **Shared key:** it belongs to Identity Center. Deleting or changing it breaks SSO and encrypted node volumes. Rotation is off.
- A missing KMS grant makes node groups fail to launch (visible at apply).
- Only EBS is covered by the CMK; S3 and EKS secrets use default encryption.
- 3 SSM endpoints cost about $0.03/hr (about $0.72/day) while they exist.
- No internet on the bastion; tools are staged through S3. Terraform's kubernetes provider cannot reach the private API.
- A Spot interruption drops the open session. Browser Session Manager cannot forward ports.
- **Deviations from brief 2.2:** no EKS audit log and no `logs` endpoint in the default run; no CloudTrail trail. The README must say so, and the law-firm answer must say production needs all three on, with dedicated keys and rotation in a separate account.
