# ADR-008: Cost optimisation choices (Spot, free S3 endpoint, default encryption keys, single working AZ)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [ADR-006](ADR-006-cluster-access-ssm-bastion.md), [ADR-007](ADR-007-terraform-structure-and-state.md), [task.md](../../task.md) sections 2.2 and 5. ADR-001 (instance type and capacity) will carry the final per-hour and per-month numbers.

## Context

Total budget is USD 150 (personal alerts are set lower). The stack is built, used and destroyed repeatedly, and the main costs are hourly: EKS control plane ($0.10/hr), interface endpoints (about $0.01/hr per AZ each), GPU nodes, bastion. Cross-AZ data transfer is charged ($0.01/GB each way).

## Decision

1. **Spot capacity** for the system nodes (Graviton), the bastion (t4g.micro) and the GPU node, with On-Demand as a documented fallback.
2. **S3 gateway VPC endpoint** (free) for ECR layer pulls, tools and model weights. Interface endpoints are created only in `platform` and destroyed when idle.
3. **Default (AWS-managed) encryption instead of a customer-managed KMS key, for the sandbox:**
   - EBS: account-default encryption with the AWS-managed `aws/ebs` key; node volumes are encrypted.
   - S3 buckets: default SSE-S3 (or the AWS-managed `aws/s3` key), public access blocked, TLS-only bucket policies.
   - EKS secrets: the EKS default encryption at rest (no envelope encryption with our own key).
   - The `kms` interface endpoint is still created, as the brief lists it.
   - The Terraform code keeps a `kms` module and a `use_cmk` variable (default `false`). Setting it to `true` would create a customer-managed key and switch EBS, S3 and EKS secrets to it, so the production-grade setup is a one-variable change. **Operator decision (2026-10-18): the CMK is not created or applied; `use_cmk` stays `false`.** The CMK path exists as reviewed code only.
4. **Single working AZ.** Two private subnets are created in two AZs (EKS and the internal ALB require subnets in at least two AZs), but nodes, the bastion, the SSM and other interface endpoints, and all pods are placed in one primary AZ (variable `primary_az`) so traffic does not cross AZs. The AZ is chosen by checking which AZ offers the needed instance types (system, g5 or equivalent) with good Spot price.
5. **No CloudWatch Logs spend in the PoC.** EKS control-plane logging is off by default (`enable_eks_control_plane_logs = false`), no Container Insights or CloudWatch agent is installed, VPC flow logs are off, and Session Manager session logging stays off. Operational logs we need are collected inside the cluster with Loki and Promtail (or Grafana Alloy) and viewed in Grafana, stored on the node or in S3 (free S3 gateway endpoint). Note that Loki/Promtail only see pod and node logs; the EKS control-plane logs (including the audit log) are produced by AWS and can only be delivered to CloudWatch Logs, so they are not available when the toggle is off.
6. No NAT gateway at all (also a cost saving, about $0.045/hr plus data) and no internet gateway.

7. **Every feature that costs money is a feature toggle, implemented in code and off by default for the PoC**, so a real deployment turns them on without code changes:

   | Toggle | Stack | Default (PoC) | What it adds when `true` | Rough cost |
   |---|---|---|---|---|
   | `use_cmk` | foundation | `false` | Customer-managed KMS key for EBS, S3, EKS secrets, logs | $1/month per key |
   | `enable_interface_endpoints` | platform | `false` until needed | ecr.api, ecr.dkr, sts, logs, kms, ec2, elasticloadbalancing | ~$0.01/hr per AZ each |
   | `enable_ssm_endpoints` | platform | `false` until needed | ssm, ssmmessages, ec2messages for the bastion | ~$0.01/hr per AZ each |
   | `enable_bastion` | platform | `false` until needed | Spot t4g.micro bastion | under $0.01/hr |
   | `enable_gpu_nodes` | platform | `false` until needed | GPU managed node group (taint, NVIDIA AMI) | ~$0.15 to $0.50/hr Spot |
   | `multi_az` | foundation, platform | `false` | Nodes, endpoints and bastion spread over both AZs | doubles endpoint cost, adds cross-AZ transfer |
   | `enable_flow_logs` | foundation | `false` | VPC flow logs to CloudWatch/S3 | log ingestion and storage |
   | `enable_eks_control_plane_logs` | platform | `false` | EKS control-plane logs (`api`, `audit`, `authenticator`) delivered to CloudWatch Logs | CloudWatch ingestion (about $0.50/GB) and storage |
   | `eks_log_retention_days` | platform | 3 | Retention for those log groups, only used when the toggle above is `true` | storage |

   The EKS control plane itself, private networking, IRSA, no-public-ingress and encryption at rest are not toggles: they stay on in every run.

## Alternatives considered

- **Customer-managed KMS key from day one.** Matches the brief literally and is better practice (key policy, rotation control, audit through CloudTrail), costing about $1/month (billed prorated hourly) plus request fees. Not applied, per operator decision to avoid any spend; kept as a code toggle only.
- **All resources spread over two AZs.** Resilient but doubles interface-endpoint cost and adds cross-AZ transfer; not needed for a single-replica sandbox.
- **On-Demand everywhere.** Predictable, but roughly 2 to 3 times the price for the GPU node.

## Consequences

Positive
- Hourly baseline stays small, and teardown is simple; cross-AZ transfer charges are close to zero.
- Encryption at rest is still on everywhere.

Negative / risks
- **Deviation from brief 2.2** ("Encrypt EBS volumes used by nodes with a customer-managed KMS key"): nodes use AWS-managed encryption and no CMK is applied. The README must state this plainly, point to the `use_cmk` toggle and the `kms` module, and explain why (sandbox cost, short-lived infra). The written law-firm answer should say a real deployment would use CMKs with a reviewed key policy and rotation.
- AWS-managed keys cannot have a custom policy, are not individually disable-able, and give less control over audit and revocation.
- Single working AZ means no AZ resilience: an AZ outage or Spot capacity shortage in that AZ stops the system. Single-AZ GPU Spot also narrows the capacity pool; fall back to another AZ or On-Demand if Spot is unavailable.
- The internal ALB still has load balancer nodes in both AZs, so a small amount of cross-AZ traffic (ALB node to pod) can occur; negligible at load-test volume.
- **Deviation from brief 2.2** ("Enable control-plane logging for the EKS cluster (`api`, `audit`, `authenticator`)"): off by default. The code supports it, so the evidence of the required setting is one variable. The README must state the deviation, and the law-firm answer must say that production needs the audit log on and shipped to an immutable store. Optional, if wanted: turn the toggle on for a short window to capture evidence; cost is only the ingested volume (a small idle cluster typically produces a few MB to a few hundred MB per day), so it is cents, but only with the operator's approval.
- Spot interruptions can disrupt demos; record evidence early.
