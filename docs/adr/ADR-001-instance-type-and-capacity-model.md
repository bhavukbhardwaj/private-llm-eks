# ADR-001: Instance types and capacity model (Spot, g5.xlarge for GPU, t4g.small for system)

- **Status:** Accepted (2026-10-18). GPU part is blocked until the AWS quota requests are approved (see Consequences).
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [ADR-008](ADR-008-cost-optimisation-choices.md), [ADR-009](ADR-009-model-sizing-strategy.md), [task.md](../../task.md) sections 2.1 and 5

## Context

The brief asks for one CPU managed node group for system workloads, one GPU managed node group on `g5.xlarge` (A10G) "or equivalent", Spot allowed, with a hard USD 150 budget. Everything must be torn down when idle. In `us-east-1` the account's G/VT quotas are Spot 0 and On-Demand 2 vCPU, and both increases to 4 vCPU (one xlarge GPU instance) are pending with AWS support (cases 179226397300403 and 179226397400130).

Spot prices sampled from the EC2 API on 2026-10-18, one hour of history, by AZ (USD per hour):

| Instance | GPU | Spot (min to max across AZs) | On-Demand list price* |
|---|---|---|---|
| g5.xlarge | A10G 24 GB | 0.429 (1c) to 0.533 (1a); 1d 0.431, 1f 0.476, 1b 0.485 | 1.006 |
| g4dn.xlarge | T4 16 GB | 0.293 (1f) to 0.350 (1a) | 0.526 |
| g5g.xlarge (Arm) | T4G 16 GB | 0.128 (1a) to 0.141 | about 0.42 |
| t4g.small | none (2 vCPU, 2 GiB) | 0.0069 (1a) to 0.0089 (1c); 1d 0.0077 | 0.0168 |
| t4g.micro | none (2 vCPU, 1 GiB) | 0.0032 (1a, 1f) to 0.0042 (1c); 1d 0.0035 | 0.0084 |

\*On-Demand prices are public list prices recalled from memory, to be re-checked against the AWS price list before the final cost table. EKS control plane is a fixed $0.10/hr.

## Decision

1. **GPU node: `g5.xlarge` on Spot** (1 x A10G 24 GB, 4 vCPU, 16 GiB RAM), one node, taint `nvidia.com/gpu=true:NoSchedule`, AL2023 NVIDIA AMI, gp3 60 GB root volume. Fallback: On-Demand `g5.xlarge` if Spot capacity is unavailable or interrupted at a critical moment; recorded when used.
2. **System node group: `t4g.small` on Spot, two nodes** (Graviton, 2 vCPU, 2 GiB each, about 11 pods per node, so about 22 pods and 4 GiB in total; aws-node, kube-proxy and two CoreDNS pods use 4 pod slots before any workload). Chosen over `t4g.micro`, which cannot hold the cluster add-ons (1 GiB, 4 pods). Revisit to `t4g.medium` if Prometheus and Grafana do not fit.
3. **Bastion: `t4g.micro` on Spot** (see ADR-006).
4. **During development use the cheapest GPU that works** (`g5g.xlarge` or `g4dn.xlarge`, or CPU only, see ADR-009) and switch to `g5.xlarge` only for the final evidence run and recording. Instance type is a single variable.
5. **Run the GPU node only while testing** (toggle `enable_gpu_nodes`, ADR-008).

### Cost estimate

| Item | Per hour | Per month if left running (730 h) |
|---|---|---|
| g5.xlarge Spot (0.43 to 0.53) | 0.43 to 0.53 | 314 to 389 |
| g5.xlarge On-Demand | 1.006 | 734 |
| Platform without GPU: EKS 0.10, t4g.small 0.0089 and t4g.micro 0.0042 Spot in 1c (about 0.013 together), 6 interface endpoints x 1 AZ 0.06, 3 SSM endpoints 0.03, internal ALB about 0.03, gp3 volumes about 0.003 | about 0.23 | about 170 |
| Platform with g5.xlarge Spot | about 0.66 to 0.76 | about 480 to 555 |

Planned use for the assessment (not 730 hours): about 40 hours of platform up and about 10 hours of GPU. That is roughly 40 x 0.23 + 10 x 0.5 = about USD 14 on Spot, against about USD 19 if the GPU hours were On-Demand. Even three times that plan stays well under the USD 150 cap. Interface endpoints also charge about $0.01 per GB processed, which is negligible at load-test volumes. Figures are estimates to be replaced by measured Cost Explorer numbers in the README.

## Alternatives considered

- **g4dn.xlarge (T4, 16 GB).** About 30 to 40 percent cheaper on Spot and a fine dev GPU, but 16 GB cannot hold a 7B model in fp16 (about 15 GB of weights plus KV cache), so the final 7B run needs quantisation or a smaller model. Used only for development.
- **g5g.xlarge (Arm + T4G).** Cheapest GPU (about 0.13 to 0.14 Spot) and consistent with Graviton nodes, but also 16 GB and a different GPU from the brief's A10G. Used only for development if desired.
- **g6.xlarge (L4 24 GB).** Same memory as A10G, newer, but not the instance the brief names and no price advantage that we have measured.
- **g5.2xlarge.** Same single A10G with more CPU and RAM at a higher price; not needed for one vLLM replica.
- **On-Demand for everything.** Predictable and no interruptions, but roughly 2.3 times the GPU cost. Kept only as a fallback.
- **t4g.micro or t4g.medium for system.** Micro is too small (see Decision 2); medium doubles memory for a few cents more per hour and is the upgrade path.

## Consequences

Positive
- GPU spend is about USD 0.43 to 0.53 per hour and only while testing, so the whole exercise fits comfortably inside USD 150.
- Final evidence uses the exact instance family the brief names (A10G, 24 GB), so a 7B fp16 model fits.
- Cheap dev GPUs and CPU-only mode keep debugging cost near zero.

Negative / risks
- **Quota dependency:** no GPU or Spot G instance can be launched until AWS approves the increases. Until then only CPU and system work can proceed (Phase 1 skeleton).
- Spot can be interrupted with two minutes notice; a single AZ narrows the capacity pool. Mitigation: record evidence early, On-Demand fallback, retry another AZ.
- t4g.small is tight: 2 GiB leaves little room, and Arm images must be available (mirrored) for add-ons; the system node is mixed-architecture with the x86 GPU node.
- Prices are estimates; a Spot spike or a forgotten node can exceed the plan, which is why budgets and teardown discipline exist.
