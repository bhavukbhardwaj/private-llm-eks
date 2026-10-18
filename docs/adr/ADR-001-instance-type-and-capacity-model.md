# ADR-001: Instance types and capacity (g5.xlarge, On-Demand because Spot had none)

- **Status:** Accepted (2026-10-18)

## Context
- The brief wants one GPU node (`g5.xlarge`, A10G) and a CPU system node. Budget is USD 150.
- GPU quota is 4 vCPU (Spot and On-Demand each), enough for one `g5.xlarge`.
- Spot prices (EC2 API, 2026-10-18, USD/hr; On-Demand list prices are from memory):

| Instance | GPU | Spot | On-Demand |
|---|---|---|---|
| g5.xlarge | A10G 24 GB | 0.43 to 0.53 | 1.006 |
| g4dn.xlarge | T4 16 GB | 0.29 to 0.35 | 0.526 |
| g5g.xlarge | T4G 16 GB (Arm) | 0.13 to 0.14 | about 0.42 |
| t4g.small | none, 2 GiB | 0.007 to 0.009 | 0.0168 |
| t4g.micro | none, 1 GiB | 0.003 to 0.004 | 0.0084 |

## Decision
- **GPU:** `g5.xlarge` in us-east-1c, taint `nvidia.com/gpu=true:NoSchedule`, gp3 60 GB, AL2023 NVIDIA image.
- **Spot first, On-Demand in the end.** Spot failed with `UnfulfillableCapacity`, also after adding g6 and g4dn and a second AZ (placement score 1 everywhere). So the GPU group runs On-Demand (`enable_gpu_ondemand_nodes`). The Spot group stays in code (`enable_gpu_nodes`).
- **System:** 2 x `t4g.small` Spot (about 11 pods each; add-ons use 4 slots per node).
- **Bastion:** `t4g.micro` Spot.
- **GPU is on only while testing.**

| Cost | Per hour | Per month (730 h) |
|---|---|---|
| Platform without GPU (EKS 0.10, nodes and bastion 0.02, 9 endpoints 0.09, ALB 0.03) | about 0.24 | about 175 |
| GPU On-Demand | 1.006 | 734 |
| GPU Spot (not available) | 0.43 to 0.53 | 314 to 389 |

Plan: about 40 h platform and 5 h GPU, roughly USD 15. Measured spend will replace this at the end.

## Alternatives considered
- **g4dn.xlarge, g5g.xlarge (16 GB):** cheaper, but a 7B model in fp16 (about 15 GB) does not fit.
- **g6.xlarge (L4, 24 GB):** not the instance the brief names; Spot price not sampled.
- **g5.2xlarge:** same GPU, more CPU for more money, and needs an 8 vCPU quota.
- **t4g.micro for system nodes:** 1 GiB and 4 pods cannot hold the add-ons.

## Consequences
**Positive**
- Final run uses the A10G the brief names; the 7B model fits.
- The GPU costs money only while the node group exists.

**Negative**
- On-Demand is about 2.3x the Spot price: about USD 1 per GPU hour.
- One GPU at a time (4 vCPU quota).
- `t4g.small` is tight on memory; `t4g.medium` is the upgrade.
- Spot interruption would cost a restart and a model re-download (not a risk now, since the GPU is On-Demand).
