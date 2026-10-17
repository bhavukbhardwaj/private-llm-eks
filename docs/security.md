# Security controls and status

Living list of security controls: what the brief or good practice requires, whether it is on in the default PoC run, and how to enable it. Cost-driven defaults are explained in [ADR-008](adr/ADR-008-cost-optimisation-choices.md). Update this table when a control changes.

| Control | Required by | Default PoC run | How to enable / note |
|---|---|---|---|
| EKS control-plane logs (`api`, `audit`, `authenticator`) | Brief 2.2; production audit requirement | **Off** (cost) | `enable_eks_control_plane_logs = true` in the platform stack; types set by `eks_control_plane_log_types`, retention by `eks_log_retention_days`. Delivered to CloudWatch Logs (about $0.50/GB). Production: also ship to an immutable store. Ask before enabling. |
| Customer-managed KMS key for node EBS volumes | Brief 2.2 | **On** once `kms_key_arn` is set (reuses the existing IAM Identity Center key; not created or destroyed by Terraform) | Set `kms_key_arn` in the untracked tfvars. S3, EKS secrets and the bastion volume use default encryption. Shared key and rotation off: see ADR-008. |
| Encryption at rest | Brief 2.2 | On (EBS default encryption, S3 SSE-S3) | Always on. |
| No public ingress to the model | Brief 2.2 | On (internal ALB only, no IGW, no NAT) | Always on. |
| Private EKS API endpoint, bastion via SSM (no inbound ports, no SSH keys) | Good practice, ADR-006 | On when the bastion toggles are used | `enable_bastion`, `enable_ssm_endpoints`. |
| IRSA for pod AWS access, no long-lived credentials | Brief 2.2 | On | Always on. Human access via SSO (ADR-004). |
| S3 Block Public Access (account-wide) | Good practice | On | Applied 2026-10-18. |
| Root MFA, no root keys, no IAM users | Good practice | On | Verified 2026-10-18. |
| CloudTrail trail | Good practice | **Off** (ADR-005) | Event History (90 days) only. |
| VPC flow logs, Container Insights, SSM session logging | Good practice | **Off** (no CloudWatch spend) | Not implemented in the PoC. |
| EC2 detailed monitoring, CloudWatch alarms/custom metrics | Not required | **Off, never enabled** (ADR-008) | Basic 5-minute metrics are free; observability comes from Prometheus/Grafana in-cluster. |
| Interface endpoint `logs` | Brief 2.2 | **Off** (nothing sends to CloudWatch) | Add `logs` to the `interface_endpoints` list when needed. |

Not done in the PoC and called out in the law-firm answer: separate AWS account, network policies, request/response audit logging with redaction, SSO in front of the API, TLS on the internal ALB with a private CA, model supply-chain verification.
