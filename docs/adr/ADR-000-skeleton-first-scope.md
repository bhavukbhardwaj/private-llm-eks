# ADR-000: Skeleton-first scope (defer GPU and LLM), Graviton Spot in a US region

- **Status:** Accepted (2026-10-18)
- **Amends:** the defaults in [deliverable.md](../../deliverable.md) (g5.xlarge Spot, Qwen model, vLLM in Phase 1/2)
- **Related:** ADR-001 (instance/capacity) and ADR-002 (model delivery) remain required deliverables and will be written when the GPU/LLM layer is added.

## Context

The brief ([task.md](../../task.md)) combines platform work (VPC, EKS, endpoints, IRSA, KMS, observability) with GPU/LLM work (g5 nodes, NVIDIA stack, vLLM, model weights). The GPU/LLM part is the expensive, quota-gated and slowest-to-debug part (GPU quota may be 0, 15 GB weights, ~$1/hr On-Demand GPU). The platform part is cheap and testable on CPU nodes. Budget is capped at USD 150.

## Decision

1. **Build a high-level skeleton first, ignoring models, GPUs and LLM serving.** Phase 1 delivers only what the platform needs: Terraform state backend, VPC (private subnets, 2+ AZs), VPC endpoints (no NAT), KMS, EKS with control-plane logging, IRSA/OIDC, AWS Load Balancer Controller, an internal ALB, and tagging. A placeholder workload (e.g. a small HTTP echo/nginx pod) stands in for vLLM to prove the internal-ALB path, IRSA, and the endpoint-only image pulls.
2. **Use Graviton (arm64) instances on Spot, in a US region (us-east-1), to keep cost minimal** while building the skeleton. Initial choice: `t4g`/`m6g`/`m7g` class (e.g. `m6g.large`) Spot for the managed node group(s). Images must be multi-arch or arm64 (mirrored into private ECR).
3. **Tweak later.** GPU node group, NVIDIA device plugin, DCGM, vLLM, model-in-S3 and the load test are added in a later phase, with the node taint/toleration and AMI already designed into the module so the change is additive.

## Alternatives considered

- **Follow the brief literally from Day 1 (g5.xlarge Spot + vLLM).** Rejected for now: highest cost per debugging hour, quota risk blocks all progress, and platform bugs get mixed with GPU bugs.
- **x86 CPU Spot (m5.large, as the brief suggests for system nodes).** Viable and avoids arm64 image concerns, but Graviton Spot is cheaper (roughly 20% lower price, better price/performance).
- **g5g.xlarge (Graviton + NVIDIA T4G) as the eventual GPU node.** Cheap and ARM-consistent, but the brief names A10G (g5) "or equivalent"; T4G is a lower-tier GPU (16 GB vs 24 GB) and a 7B fp16 model will not fit comfortably. To be decided in ADR-001, not here.

## Consequences

Positive
- Much lower spend while iterating; GPU hours used only for final proof and recording.
- Platform correctness (no-NAT image pulls, IRSA, internal ALB, SGs, logging) is proven independently of GPU issues.
- GPU quota requests can proceed in parallel without blocking.

Negative / risks
- **Deviates from the brief's assessment order:** the top-weighted criterion (a GPU pod really runs `nvidia-smi`) is not satisfied until the GPU phase is done. The GPU phase must not be skipped or squeezed out; schedule it with enough time before the ~2026-10-19 due date.
- Graviton is arm64 but GPU nodes (g5, A10G) are x86_64. The final cluster is therefore **mixed-architecture**: system pods can run on arm64, GPU workloads on x86. All shared images (LB controller, Prometheus stack, etc.) need multi-arch builds or per-arch node selectors; mirrored ECR images must include the right architectures.
- Spot interruptions on system nodes can cause brief control-plane add-on churn; acceptable for a sandbox, noted as a known limitation in the README.
- Placeholder workload results (latency, throughput) are not representative and must not be reported as LLM results.

## Follow-ups
- Update phase list in `deliverable.md` (done in this change).
- Write ADR-001 and ADR-002 when GPU/LLM scope is reintroduced.
