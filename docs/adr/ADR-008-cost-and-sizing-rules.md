# ADR-008: Cost and sizing rules (Spot, no NAT, gp3, toggles)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-001](ADR-001-instance-type-and-capacity-model.md), [ADR-010](ADR-010-encryption-with-existing-kms-key.md), [ADR-011](ADR-011-logging-and-monitoring-defaults.md), [ADR-012](ADR-012-single-working-az.md), [task.md](../../task.md) section 5 (budget USD 150)

## Context
- Budget cap USD 150. Personal alerts: $20/day and $50/month.
- Hourly costs dominate: EKS $0.10/hr, interface endpoints about $0.01/hr per AZ each, GPU $0.43 to $0.53/hr Spot, ALB about $0.03/hr.
- The stack is built, used and destroyed repeatedly.

## Decision
**Rules**
- **Spot** for system nodes, bastion and GPU (ADR-001).
- **No NAT, no internet gateway.** Saves about $0.045/hr, which is about $33/month, plus $0.045/GB processed.
- **Free S3 gateway endpoint** for ECR layers, tools and model weights.
- **gp3 only, never gp2:** $0.08 vs $0.10 per GB-month, includes 3,000 IOPS and 125 MB/s. No provisioned IOPS, no snapshots.
- **Smallest working sizes:** system node 20 GB, bastion 10 GB, GPU node 60 GB (7B run; 40 GB is enough for 0.5B). About 110 GB in total (2 x 20 + 10 + 60), about $8.80/month, against $11.00 on gp2.
- **EKS default `gp2` StorageClass is replaced by a `gp3` default** in `k8s/`. PoC workloads prefer `emptyDir` over PVCs.
- **No EC2 detailed monitoring** (`monitoring = false`): the 1-minute metrics cost about $2.10 per instance-month. Basic 5-minute metrics are free. No CloudWatch alarms or custom metrics. Metrics come from Prometheus and Grafana.
- **Do not assume free-tier eligibility.** Check Billing before relying on it.

**Cost toggles** (variables in code, off by default for the PoC; never turned on without asking)

| Toggle | Default | Adds when on | Cost |
|---|---|---|---|
| `enable_interface_endpoints` | false | ecr.api, ecr.dkr, sts, kms, ec2, elasticloadbalancing (6) | about $0.06/hr (1 AZ) |
| `enable_ssm_endpoints` | false | ssm, ssmmessages, ec2messages (3) | about $0.03/hr |
| `enable_bastion` | false | Spot `t4g.micro` | about $0.004/hr |
| `enable_gpu_nodes` | false | GPU node group | about $0.43 to $0.53/hr |
| `kms_key_arn` | null | Node EBS encrypted with the existing key (ADR-010) | $0 extra |
| `enable_eks_control_plane_logs` | false | EKS logs to CloudWatch (ADR-011) | about $0.50/GB ingested |
| `multi_az` | false | Nodes and endpoints in both AZs | doubles endpoint cost |

- Not toggles (always on): private networking, no public ingress, IRSA, encryption at rest, the EKS control plane.

## Alternatives considered
- **On-Demand everywhere:** about 2.3x for GPU (1.006 vs 0.43 to 0.53 $/hr).
- **NAT gateway:** $33/month fixed plus per-GB, and against the brief for model traffic.
- **gp2 volumes:** 25% more per GB for fewer IOPS.
- **Always-on cluster:** about $0.24/hr, roughly $175/month. Over budget in one month.
- **Detailed monitoring:** about $2.10 per instance-month for no benefit.

## Consequences
**Positive**
- Idle baseline is near zero: nothing hourly exists until `platform` is applied.
- Planned total is about USD 15 against the USD 150 cap (ADR-001).
- Teardown is one `terraform destroy` in `platform`.

**Negative**
- With toggles off the cluster is unusable (nodes cannot pull images without the endpoints), so every working session turns them on.
- Spot interruptions can disrupt a demo; evidence is recorded early.
- Without detailed monitoring and CloudWatch alarms, a forgotten node is caught only by the budget emails.
- 20 GB system volumes leave little headroom for large local images.
