# ADR-001: Instance types and capacity model (Spot only)

- **Status:** Accepted (2026-10-18). Quotas verified live at 02:25 IST: Spot G/VT 4 vCPU, On-Demand G/VT 4 vCPU.
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [ADR-008](ADR-008-cost-and-sizing-rules.md), [ADR-009](ADR-009-model-sizing-strategy.md), [ADR-012](ADR-012-single-working-az.md)

## Context
- The brief wants a CPU system node group and one GPU group (`g5.xlarge`, A10G, or equivalent). Spot is allowed.
- Budget is USD 150 and everything is torn down when idle.
- Quota limit is 4 vCPU, which is exactly one xlarge GPU instance.
- Spot prices, EC2 API, 2026-10-18 (USD/hr):

| Instance | GPU | Spot (min to max over AZs) | On-Demand list* |
|---|---|---|---|
| g5.xlarge | A10G 24 GB | 0.429 (1c) to 0.533 (1a) | 1.006 |
| g4dn.xlarge | T4 16 GB | 0.293 to 0.350 | 0.526 |
| g5g.xlarge (Arm) | T4G 16 GB | 0.128 to 0.141 | about 0.42 |
| t4g.small | none, 2 vCPU, 2 GiB | 0.0069 to 0.0089 | 0.0168 |
| t4g.micro | none, 2 vCPU, 1 GiB | 0.0032 to 0.0042 | 0.0084 |

\*List prices are from memory. Re-check before the final cost table. EKS control plane is $0.10/hr.

## Decision
- **GPU node:** `g5.xlarge` on **Spot**, one node, AL2023 NVIDIA AMI, taint `nvidia.com/gpu=true:NoSchedule`, gp3 60 GB.
- **Spot only (operator decision):** it is a PoC, so we do not pay On-Demand.
- **Fallback kept in code:** variable `gpu_capacity_type` (default `SPOT`, `ON_DEMAND` possible), commented as unused.
- **System nodes:** `t4g.small` Spot, **two** nodes (about 11 pods each; add-ons take 4 slots per node).
- **Bastion:** `t4g.micro` Spot (ADR-006).
- **Develop on the cheapest GPU or CPU**, switch to `g5.xlarge` for the final evidence run. One variable changes it.
- **GPU runs only while testing** (toggle `enable_gpu_nodes`).

**Cost estimate**

| Item | Per hour | Per month (730 h) |
|---|---|---|
| g5.xlarge Spot | 0.43 to 0.53 | 314 to 389 |
| g5.xlarge On-Demand (not used) | 1.006 | 734 |
| Platform without GPU (EKS 0.10, 2 x t4g.small + bastion about 0.02, 6 interface endpoints 0.06, 3 SSM endpoints 0.03, ALB about 0.03) | about 0.24 | about 175 |
| Platform with g5 Spot | about 0.67 to 0.77 | about 490 to 560 |

- Planned use: about 40 h platform + 10 h GPU = roughly **USD 15**. Estimates to be replaced by Cost Explorer numbers.

## Alternatives considered
- **`g4dn.xlarge` (T4, 16 GB):** about 35% cheaper, but 7B fp16 does not fit. Dev use only.
- **`g5g.xlarge` (Arm, T4G, 16 GB):** cheapest, same memory limit, not the brief's A10G. Dev use only.
- **`g6.xlarge` (L4, 24 GB):** same memory, but not the instance the brief names; no measured price gain.
- **`g5.2xlarge`:** same GPU, more CPU and RAM for more money; not needed for one replica.
- **On-Demand:** about 2.3x the cost; kept only as an unused fallback.
- **`t4g.micro` for system nodes:** 1 GiB and 4 pods, cannot hold the add-ons. `t4g.medium` is the upgrade path.

## Consequences
**Positive**
- GPU costs about $0.43 to $0.53/hr and only while testing.
- Final run uses the instance family the brief names, so a 7B fp16 model fits.
- Cheap dev GPUs keep debugging cost near zero.

**Negative**
- Only one GPU instance at a time (4 vCPU quota, Spot and On-Demand do not add up).
- Worst case of Spot, in order:
  - 2-minute warning, node is reclaimed, in-flight requests fail.
  - Replacement node starts if capacity exists.
  - Init container re-downloads weights (about 30 s for 1 GB, 2 to 4 min for 7B).
  - `emptyDir` and in-memory Prometheus data are lost.
  - No capacity in the AZ means the pod stays Pending; try `g4dn.xlarge` or the other AZ.
  - Nothing permanent is lost and nothing extra is billed.
- `t4g.small` is tight on memory; may need `t4g.medium` for Prometheus.
- Prices are estimates; a forgotten node can overspend (budgets and teardown cover this).
