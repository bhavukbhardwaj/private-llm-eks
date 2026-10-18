# ADR-003: Cost and sizing (Spot, no NAT, gp3, one working AZ, toggles)

- **Status:** Accepted (2026-10-18)

## Context
- Budget USD 150. Hourly items dominate: EKS $0.10, interface endpoints about $0.01 per AZ each, GPU $1.01 (On-Demand), ALB about $0.03.
- EKS and the ALB need subnets in two AZs. Cross-AZ data costs $0.01/GB each way.
- g5.xlarge Spot by AZ (2026-10-18): 1c $0.429, 1d $0.431, 1f $0.476, 1b $0.485, 1a $0.533.

## Decision
- **Spot** for system nodes and bastion.
- **No NAT, no internet gateway:** saves $0.045/hr (about $33/month). The free S3 gateway endpoint serves ECR layers, tools and weights.
- **gp3 only:** $0.08 vs $0.10 per GB-month. Sizes: system 20 GB, bastion 10 GB, GPU 60 GB (110 GB, about $8.80/month vs $11 on gp2). No PVCs, so no storage class.
- **No EC2 detailed monitoring** (about $2.10 per instance-month) and no CloudWatch alarms. Metrics come from Prometheus.
- **Two subnets, one working AZ:** subnets in `us-east-1c` and `1d` (the cheapest g5 Spot AZs); all nodes, endpoints and pods in 1c. 1d is the spare.
- **Everything that bills by the hour is a toggle, off by default:**

| Toggle | Adds | Cost |
|---|---|---|
| `enable_interface_endpoints` | 6 endpoints (ecr, sts, kms, ec2, elb) | $0.06/hr |
| `enable_ssm_endpoints` | 3 SSM endpoints | $0.03/hr |
| `enable_bastion` | Spot t4g.micro | $0.004/hr |
| `enable_gpu_ondemand_nodes` | GPU node, On-Demand | $1.01/hr |
| `enable_gpu_nodes` | GPU node, Spot (no capacity) | $0.43 to 0.53/hr |
| `enable_eks_control_plane_logs` | EKS logs to CloudWatch | about $0.50/GB |
| `kms_key_arn` | node EBS on the existing key | $0 extra |

## Alternatives considered
- **NAT gateway:** $33/month plus $0.045/GB, and against the brief.
- **gp2:** 25% more per GB, fewer IOPS.
- **Both AZs for nodes:** about $0.09/hr more for endpoints, plus cross-AZ traffic.
- **us-east-1a and 1b:** 1a is the dearest g5 Spot AZ.
- **Always-on cluster:** about $175/month.

## Consequences
**Positive**
- Nothing bills by the hour until `platform` is applied; teardown is one `terraform destroy`.
- Planned total about USD 15 against the USD 150 cap.

**Negative**
- With the endpoints off the cluster cannot pull images, so every session turns them on.
- One AZ means no AZ resilience.
- The ALB still has nodes in both AZs, so a little traffic crosses AZs (negligible).
- Without alarms, a forgotten node is caught only by budget emails.
