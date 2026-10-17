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
5. **No CloudWatch Logs spend by default; EKS control-plane logging is supported but off.** Operator decision (2026-10-18, refined): the PoC must not pay for CloudWatch Logs, but the audit capability must exist in code. The platform stack has `enable_eks_control_plane_logs` (default `false`) and `eks_control_plane_log_types` (default `["api", "audit", "authenticator"]`, used only when enabled) plus `eks_log_retention_days` (default 3). When the toggle is `false`, no log types are enabled and no log group is created. Turning it on is a deliberate, approved action (it is a production requirement, see [docs/security.md](../security.md)). Everything else that would send to CloudWatch stays absent: no VPC flow logs, no Container Insights or CloudWatch agent, no Session Manager session logging. The `logs` interface endpoint is dropped from the default endpoint set (list variable `interface_endpoints`; add it back when the EKS toggle or any other CloudWatch use is enabled, since the log delivery for EKS itself is done by the control plane, but pods or agents sending logs from private nodes need it). Operational logs we need are collected inside the cluster with Loki and Promtail (or Grafana Alloy) and read in Grafana, stored on node disk or in S3. Loki only sees pod and node logs; it cannot replace the EKS audit log, which AWS delivers only to CloudWatch Logs.
6. **No detailed (1-minute) CloudWatch monitoring anywhere.** EC2 detailed monitoring is not enabled on any instance, launch template or node group (`monitoring = false`, the default basic 5-minute metrics are free), and no CloudWatch alarms or custom CloudWatch metrics are created. Metrics come from Prometheus (in-cluster: vLLM, DCGM, node exporter) and Grafana. This is not a toggle; it is a rule for this PoC.
7. No NAT gateway at all (also a cost saving, about $0.045/hr plus data) and no internet gateway.

8. **Every feature that costs money is a feature toggle, implemented in code and off by default for the PoC**, so a real deployment turns them on without code changes:

   | Toggle | Stack | Default (PoC) | What it adds when `true` | Rough cost |
   |---|---|---|---|---|
   | `use_cmk` | foundation | `false` | Customer-managed KMS key for EBS, S3, EKS secrets, logs | $1/month per key |
   | `enable_eks_control_plane_logs` | platform | `false` | EKS control-plane logs (`api`, `audit`, `authenticator`) to CloudWatch Logs | about $0.50/GB ingested plus storage |
   | `enable_interface_endpoints` | platform | `false` until needed | ecr.api, ecr.dkr, sts, kms, ec2, elasticloadbalancing (`logs` excluded by the no-CloudWatch rule; list is the `interface_endpoints` variable) | ~$0.01/hr per AZ each |
   | `enable_ssm_endpoints` | platform | `false` until needed | ssm, ssmmessages, ec2messages for the bastion | ~$0.01/hr per AZ each |
   | `enable_bastion` | platform | `false` until needed | Spot t4g.micro bastion | under $0.01/hr |
   | `enable_gpu_nodes` | platform | `false` until needed | GPU managed node group (taint, NVIDIA AMI) | ~$0.15 to $0.50/hr Spot |
   | `multi_az` | foundation, platform | `false` | Nodes, endpoints and bastion spread over both AZs | doubles endpoint cost, adds cross-AZ transfer |

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
- **Default run deviates from brief 2.2** ("Enable control-plane logging for the EKS cluster (`api`, `audit`, `authenticator`)") and from the brief's `logs` endpoint, because both are off or absent by default. The capability is implemented behind `enable_eks_control_plane_logs`, so enabling it is one variable. The README must state the default and how to enable it, and [docs/security.md](../security.md) lists it as a required production control.
- Spot interruptions can disrupt demos; record evidence early.
