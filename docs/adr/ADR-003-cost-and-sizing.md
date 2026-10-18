# ADR-003: Cost and sizing (Spot, no NAT, gp3, one working AZ, toggles)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-001](ADR-001-instance-type-and-capacity-model.md), [ADR-004](ADR-004-security.md), [task.md](../../task.md) section 5 (budget USD 150)
- **Index:** D1 Spot, D2 no NAT, D3 gp3 and sizes, D4 no detailed monitoring, D5 working AZ, D6 cost toggles

## Context
- Budget cap USD 150. Personal alerts: $20/day and $50/month.
- Hourly items dominate: EKS $0.10, interface endpoints about $0.01 per AZ each, GPU $0.43 to $0.53 (Spot), ALB about $0.03.
- The stack is built, used and destroyed repeatedly.
- EKS and the internal ALB need subnets in at least two AZs. Cross-AZ data costs $0.01/GB each way.
- g5.xlarge Spot by AZ (EC2 API, last hour, 2026-10-18): 1c $0.429, 1d $0.431, 1f $0.476, 1b $0.485, 1a $0.533.

## Decision
- **D1 Spot** for system nodes, bastion and GPU (ADR-001).
- **D2 No NAT and no internet gateway.** Saves $0.045/hr (about $33/month) plus $0.045/GB. Use the free S3 gateway endpoint for ECR layers, tools and model weights.
- **D3 gp3 only, never gp2.**
  - $0.08 vs $0.10 per GB-month; 3,000 IOPS and 125 MB/s included; no provisioned IOPS, no snapshots.
  - Sizes: system node 20 GB, bastion 10 GB, GPU node 60 GB (40 GB is enough for 0.5B).
  - Total 110 GB (2 x 20 + 10 + 60): about $8.80/month vs $11.00 on gp2.
  - Replace the EKS default `gp2` StorageClass with a `gp3` default in `k8s/`. Prefer `emptyDir` over PVCs.
- **D4 No EC2 detailed monitoring** (`monitoring = false`).
  - The paid 1-minute metrics cost about $2.10 per instance-month. Basic 5-minute metrics are free.
  - No CloudWatch alarms or custom metrics. Metrics come from Prometheus and Grafana.
- **D5 Two subnets, one working AZ.**
  - Subnets in `us-east-1c` and `us-east-1d` (the two cheapest g5 Spot AZs). VPC `10.20.0.0/16`, subnets `10.20.1.0/24` and `10.20.2.0/24`.
  - Working AZ is **1c** (`primary_az`): all nodes, bastion, endpoints and pods. 1d is the spare and the fallback.
  - Exception: the GPU node group may use both subnets (1c and 1d) to widen the Spot pool. Endpoints stay in 1c, so a node in 1d adds a little cross-AZ traffic.
  - `describe-instance-type-offerings`: t4g.small, t4g.micro, g5.xlarge, g4dn.xlarge and g5g.xlarge exist in both.
  - "1d is less crowded" cannot be verified; the choice rests on price.
- **D6 Cost toggles**: variables, implemented in code, off by default, never turned on without asking.

| Toggle | Default | Adds when on | Cost |
|---|---|---|---|
| `enable_interface_endpoints` | false | ecr.api, ecr.dkr, sts, kms, ec2, elasticloadbalancing (6) | about $0.06/hr |
| `enable_ssm_endpoints` | false | ssm, ssmmessages, ec2messages (3) | about $0.03/hr |
| `enable_bastion` | false | Spot `t4g.micro` | about $0.004/hr |
| `enable_gpu_nodes` | false | Spot GPU node group | $0.43 to $0.53/hr |
| `enable_gpu_ondemand_nodes` | false | On-Demand GPU node group (Spot fallback, owner approval) | about $1.01/hr |
| `kms_key_arn` | null | Node EBS on the existing key (ADR-004) | $0 extra |
| `enable_eks_control_plane_logs` | false | EKS logs to CloudWatch (ADR-004) | about $0.50/GB |
| `multi_az` | false | Nodes and endpoints in both AZs | doubles endpoint cost |

- Always on: private networking, no public ingress, IRSA, encryption at rest, the EKS control plane.
- Do not assume free-tier eligibility; check Billing first.

## Alternatives considered
- **D1 On-Demand:** about 2.3x for GPU ($1.006 vs $0.43 to $0.53).
- **D2 NAT gateway:** $33/month fixed plus per-GB, and against the brief for model traffic.
- **D3 gp2:** 25% more per GB for fewer IOPS.
- **D4 Detailed monitoring:** about $2.10 per instance-month for no benefit.
- **D5 Both AZs for nodes:** resilient, but about $0.09/hr more for 9 endpoints plus cross-AZ transfer.
- **D5 us-east-1a and 1b:** 1a is the dearest g5 Spot AZ ($0.533, about $1 more over 10 GPU hours).
- **Always-on cluster:** about $0.24/hr, about $175/month. Over budget in one month.

## Consequences
**Positive**
- Nothing bills by the hour until `platform` is applied.
- Planned total about USD 15 against the USD 150 cap (ADR-001).
- Teardown is one `terraform destroy` in `platform`.
- Near-zero cross-AZ cost and one set of endpoints.

**Negative**
- With toggles off the cluster is unusable (nodes cannot pull images), so each session turns the endpoints on.
- No AZ resilience: an AZ outage or no Spot capacity in 1c stops the system. Fallback is `primary_az = us-east-1d` or `g4dn.xlarge`.
- The ALB still has nodes in both AZs, so a little ALB-to-pod traffic can cross AZs. Negligible at load-test volume.
- Without alarms, a forgotten node is caught only by the budget emails.
- 20 GB system volumes leave little room for big local images.
- One hour of Spot history is a thin sample.
