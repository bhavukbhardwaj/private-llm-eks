# ADR-008: Cost optimisation choices (Spot, free S3 endpoint, default encryption keys, single working AZ)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [ADR-006](ADR-006-cluster-access-ssm-bastion.md), [ADR-007](ADR-007-terraform-structure-and-state.md), [task.md](../../task.md) sections 2.2 and 5. ADR-001 (instance type and capacity) will carry the final per-hour and per-month numbers.

## Context

Total budget is USD 150 (personal alerts are set lower). The stack is built, used and destroyed repeatedly, and the main costs are hourly: EKS control plane ($0.10/hr), interface endpoints (about $0.01/hr per AZ each), GPU nodes, bastion. Cross-AZ data transfer is charged ($0.01/GB each way).

## Decision

1. **Spot capacity** for the system node (t4g.small), the bastion (t4g.micro) and the GPU node, with On-Demand as a documented fallback.
2. **S3 gateway VPC endpoint** (free) for ECR layer pulls, tools and model weights. Interface endpoints are created only in `platform` and destroyed when idle.
3. **Encryption: reuse the existing customer-managed KMS key for node EBS volumes; default encryption elsewhere.** Operator decision (2026-10-18, revised): the account already has a customer-managed key, created by IAM Identity Center (description "IAM Identity Center customer managed key"), so reusing it adds no monthly cost and meets brief 2.2 ("Encrypt EBS volumes used by nodes with a customer-managed KMS key").
   - Terraform **only references the key by ARN** (variable `kms_key_arn`, passed from an untracked tfvars file because the ARN contains the account ID). It never creates, modifies or destroys the key, so `terraform destroy` leaves it untouched. The key policy is not edited: it already lets the account root delegate access, so the only extra is one `aws_kms_grant` allowing the Auto Scaling service-linked role to use the key when it launches node group instances.
   - Used for: system and GPU node root volumes (launch templates, `encrypted = true`, `kms_key_id = <key>`). This is what the brief writes. Not used for: S3 (SSE-S3 with TLS-only policies and public access blocked), EKS secrets (EKS default encryption at rest), the bastion root volume (AWS-managed `aws/ebs`, because a persistent Spot request would additionally need a grant for the EC2 Spot service-linked role, which does not exist yet), or ECR (AES256).
   - Account-level EBS default encryption is **not** enabled (checked 2026-10-18); every volume we create sets `encrypted = true` explicitly.
   - `kms_key_arn = null` (the default) keeps AWS-managed encryption, so the setting can be switched off without other changes.
   - The `kms` interface endpoint stays in the endpoint list, as the brief names it; nodes do not call KMS directly for EBS, so it is a small, mostly idle cost.
4. **Single working AZ.** Two private subnets are created in two AZs (EKS and the internal ALB require subnets in at least two AZs), but nodes, the bastion, the SSM and other interface endpoints, and all pods are placed in one primary AZ (variable `primary_az`) so traffic does not cross AZs. **Chosen by the operator (2026-10-18, revised): subnets in `us-east-1c` and `us-east-1d`, working AZ `us-east-1c`.** Source: `aws ec2 describe-spot-price-history` for the last hour on 2026-10-18. g5.xlarge Spot: 1c $0.429, 1d $0.431, 1f $0.476, 1b $0.485, 1a $0.533, so 1c and 1d are the two cheapest AZs. g4dn.xlarge and g5g.xlarge are also offered in 1c and 1d. Reasoning is that a lower Spot price is a rough signal of lower demand in that AZ; this is a market signal, not a guarantee of capacity, and one hour of history is a thin sample. The operator's expectation that 1d is less used by the general public is not something we can verify. Confirmed on 2026-10-18 with `describe-instance-type-offerings`: t4g.small, t4g.micro, g5.xlarge, g4dn.xlarge and g5g.xlarge are all offered in both 1c and 1d. If 1c runs short of Spot capacity, `primary_az` can be switched to 1d (the other subnet already exists).
5. **No CloudWatch Logs spend by default; EKS control-plane logging is supported but off.** Operator decision (2026-10-18, refined): the PoC must not pay for CloudWatch Logs, but the audit capability must exist in code. The platform stack has `enable_eks_control_plane_logs` (default `false`) and `eks_control_plane_log_types` (default `["api", "audit", "authenticator"]`, used only when enabled) plus `eks_log_retention_days` (default 3). When the toggle is `false`, no log types are enabled and no log group is created. Turning it on is a deliberate, approved action (it is a production requirement, see [docs/security.md](../security.md)). Everything else that would send to CloudWatch stays absent: no VPC flow logs, no Container Insights or CloudWatch agent, no Session Manager session logging. The `logs` interface endpoint is dropped from the default endpoint set (list variable `interface_endpoints`; add it back when the EKS toggle or any other CloudWatch use is enabled, since the log delivery for EKS itself is done by the control plane, but pods or agents sending logs from private nodes need it). Operational logs we need are collected inside the cluster with Loki and Promtail (or Grafana Alloy) and read in Grafana, stored on node disk or in S3. Loki only sees pod and node logs; it cannot replace the EKS audit log, which AWS delivers only to CloudWatch Logs.
6. **No detailed (1-minute) CloudWatch monitoring anywhere.** EC2 detailed monitoring is not enabled on any instance, launch template or node group (`monitoring = false`, the default basic 5-minute metrics are free), and no CloudWatch alarms or custom CloudWatch metrics are created. Metrics come from Prometheus (in-cluster: vLLM, DCGM, node exporter) and Grafana. This is not a toggle; it is a rule for this PoC.
7. **EBS is gp3 only, never gp2, and every size is the smallest that works.**
   - Every EBS volume in Terraform (node root volumes via launch templates, bastion root volume) sets `volume_type = "gp3"` with encryption on. gp3 is about 20% cheaper per GB than gp2 ($0.08 vs $0.10 per GB-month) and includes 3,000 IOPS and 125 MB/s with no extra charge, so no extra IOPS or throughput is provisioned.
   - Kubernetes: EKS ships a default `gp2` StorageClass. We create a `gp3` StorageClass (EBS CSI driver) in `k8s/` and make it the default, and unset the `gp2` default. Workloads avoid PVCs where possible (`emptyDir` for the model copy and for Prometheus in the PoC); any PVC uses `gp3` and a minimal size.
   - Default sizes (variables, overridable): system node 20 GB, bastion 10 GB, GPU node 60 GB for the 7B run (vLLM image plus about 15 GB of weights plus headroom; 40 GB is enough for a small dev model). No snapshots, no provisioned IOPS.
   - General rule: size every resource at the minimum that works and use free allowances where they exist (S3 gateway endpoint, basic EC2 metrics, free-tier-eligible sizes). Do not assume free-tier eligibility for this account; verify in Billing before relying on it.
8. No NAT gateway at all (also a cost saving, about $0.045/hr plus data) and no internet gateway.

9. **Every feature that costs money is a feature toggle, implemented in code and off by default for the PoC**, so a real deployment turns them on without code changes:

   | Toggle | Stack | Default (PoC) | What it adds when `true` | Rough cost |
   |---|---|---|---|---|
   | `kms_key_arn` | platform | `null` (set it to use the existing customer-managed key) | Node EBS volumes encrypted with that key plus one KMS grant | $0 extra (the key already exists; requests about $0.03 per 10,000) |
   | `enable_eks_control_plane_logs` | platform | `false` | EKS control-plane logs (`api`, `audit`, `authenticator`) to CloudWatch Logs | about $0.50/GB ingested plus storage |
   | `enable_interface_endpoints` | platform | `false` until needed | ecr.api, ecr.dkr, sts, kms, ec2, elasticloadbalancing (`logs` excluded by the no-CloudWatch rule; list is the `interface_endpoints` variable) | ~$0.01/hr per AZ each |
   | `enable_ssm_endpoints` | platform | `false` until needed | ssm, ssmmessages, ec2messages for the bastion | ~$0.01/hr per AZ each |
   | `enable_bastion` | platform | `false` until needed | Spot t4g.micro bastion | under $0.01/hr |
   | `enable_gpu_nodes` | platform | `false` until needed | GPU managed node group (taint, NVIDIA AMI) | ~$0.15 to $0.50/hr Spot |
   | `multi_az` | foundation, platform | `false` | Nodes, endpoints and bastion spread over both AZs | doubles endpoint cost, adds cross-AZ transfer |

   The EKS control plane itself, private networking, IRSA, no-public-ingress and encryption at rest are not toggles: they stay on in every run.

## Alternatives considered

- **Create a new customer-managed KMS key.** Cleaner separation and our own key policy, but about $1/month more and a second key to manage and delete (7 to 30 day deletion window). Rejected in favour of reusing the Identity Center key.
- **AWS-managed encryption only.** Free and simplest, but it does not meet the brief's customer-managed key line; rejected once the existing key was found.
- **All resources spread over two AZs.** Resilient but doubles interface-endpoint cost and adds cross-AZ transfer; not needed for a single-replica sandbox.
- **On-Demand everywhere.** Predictable, but roughly 2 to 3 times the price for the GPU node.

## Consequences

Positive
- Hourly baseline stays small, and teardown is simple; cross-AZ transfer charges are close to zero.
- Encryption at rest is still on everywhere.

Negative / risks
- **Shared key:** the key belongs to IAM Identity Center. If it is deleted or its policy changes, SSO login and our node volumes are affected. Mitigation: we never touch the key, and destroying our stack removes only our grant. Key rotation is currently off (not required by the brief). For production, a dedicated key per purpose with rotation and a reviewed policy, in a separate account, is the right design; the law-firm answer must say so.
- If the Auto Scaling grant is missing or wrong, node groups fail to launch instances (an immediate, visible error at apply); setting `kms_key_arn = null` returns to AWS-managed encryption.
- AWS-managed keys cannot have a custom policy, are not individually disable-able, and give less control over audit and revocation.
- Single working AZ means no AZ resilience: an AZ outage or Spot capacity shortage in that AZ stops the system. Single-AZ GPU Spot also narrows the capacity pool; fall back to another AZ or On-Demand if Spot is unavailable.
- The internal ALB still has load balancer nodes in both AZs, so a small amount of cross-AZ traffic (ALB node to pod) can occur; negligible at load-test volume.
- **Default run deviates from brief 2.2** ("Enable control-plane logging for the EKS cluster (`api`, `audit`, `authenticator`)") and from the brief's `logs` endpoint, because both are off or absent by default. The capability is implemented behind `enable_eks_control_plane_logs`, so enabling it is one variable. The README must state the default and how to enable it, and [docs/security.md](../security.md) lists it as a required production control.
- Spot interruptions can disrupt demos; record evidence early.
