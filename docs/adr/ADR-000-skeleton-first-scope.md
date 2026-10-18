# ADR-000: Skeleton first, GPU and LLM later (Graviton Spot, us-east-1)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-001](ADR-001-instance-type-and-capacity-model.md), [ADR-003](ADR-003-image-supply-without-nat.md), [ADR-009](ADR-009-model-sizing-strategy.md)

## Context
- The brief mixes platform work (VPC, EKS, IRSA, endpoints) with GPU/LLM work (g5 node, NVIDIA stack, vLLM, weights).
- GPU/LLM is the costly part: quota-gated, about $0.43/hr Spot, slowest to debug.
- The platform part is cheap and can be tested on CPU nodes.
- Hard budget: USD 150.

## Decision
- Build the platform skeleton first: state, VPC, endpoints, EKS, IRSA, LB controller, internal ALB.
- Use a placeholder pod to prove the ALB path, IRSA and image pulls.
- Add GPU node, device plugin, DCGM, vLLM, model and load test afterwards. The taint and AMI are already in the module, so it is additive.
- Use Graviton (arm64) Spot in us-east-1: `t4g.small` system node, `t4g.micro` bastion.
- Pull all images from private ECR, multi-arch where needed (ADR-003).

## Alternatives considered
- **Follow the brief literally from day 1 (GPU + vLLM):** rejected. Highest cost per debug hour, quota risk, and platform bugs mix with GPU bugs.
- **x86 `m5.large` for system nodes (the brief's example):** rejected. About 20% dearer than Graviton Spot, and no arm64 benefit.
- **`g5g.xlarge` (Arm + T4G) as the final GPU:** rejected for the final run. 16 GB GPU is too small for 7B fp16 (see ADR-001).

## Consequences
**Positive**
- Low spend while iterating.
- Platform is proven separately from GPU issues.
- GPU quota request ran in parallel.

**Negative**
- The top-graded item (`nvidia-smi` on a real GPU pod) comes last and must not be squeezed out.
- Cluster is mixed-architecture: arm64 system nodes, x86 GPU node. Images need the right platform.
- Spot churn on system nodes can briefly disturb add-ons.
- Placeholder numbers are not LLM results and must not be reported as such.
