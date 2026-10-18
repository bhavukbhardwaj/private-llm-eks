# ADR-006: Scope and model strategy (skeleton first, small model first)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-001](ADR-001-instance-type-and-capacity-model.md), [ADR-002](ADR-002-model-delivery-into-cluster.md), [task.md](../../task.md) section 2.3
- **Index:** D1 skeleton first, D2 small model first, 7B for the final run

## Context
- The brief mixes platform work (VPC, EKS, IRSA, endpoints) with GPU/LLM work (g5 node, NVIDIA stack, vLLM, weights).
- GPU/LLM is the costly part: quota-gated, about $0.43/hr Spot, slowest to debug. The platform part is cheap and testable on CPU.
- The brief asks for a 7B-class model on one A10G. What is graded is the platform end to end (GPU schedules, `nvidia-smi`, S3 via IRSA, probes, metrics), not model quality.
- A model change only changes `--model`, `--served-model-name`, `--max-model-len`, `--gpu-memory-utilization` and maybe dtype. Terraform, manifests, dashboard and load test stay the same.
- 7B fp16 is about 15 GB: S3 storage is about $0.35/month. Size costs time, not money. GPU hourly price does not depend on model size.

## Decision
**D1 Platform skeleton first, GPU and LLM after**
- Build state, VPC, endpoints, EKS, IRSA, LB controller and internal ALB first.
- A placeholder pod proves the ALB path, IRSA and image pulls.
- GPU node, device plugin, DCGM, vLLM, model and load test come next. The taint and AMI are already in the module, so it is additive.
- Graviton Spot in us-east-1 for the skeleton (ADR-001, ADR-003).

**D2 Small model for development, 7B for the final run**
- Dev: Qwen2.5-0.5B-Instruct (about 1 GB), revision `7ae557604adf67be50417f59c2c2f167def9a775`.
- Final demo: Qwen2.5-7B-Instruct at a pinned revision on `g5.xlarge`, if time and budget allow. Same manifests; change only arguments and the S3 prefix.
- The final system uses a real GPU. The top criterion needs a GPU pod.
- Optional CPU stage: vLLM CPU backend on Graviton, or a stub. A ready-made arm64 vLLM CPU image is **not verified**; building it is the fallback.
- Exact model, revision and vLLM arguments with reasons go in the README.

## Alternatives considered
- **D1 GPU and vLLM from day 1:** highest cost per debug hour; platform and GPU bugs mix.
- **D1 x86 `m5.large` system nodes:** about 20% dearer than Graviton Spot, no benefit.
- **D1 `g5g.xlarge` as the final GPU:** 16 GB cannot hold 7B fp16 (ADR-001).
- **D2 7B from the start:** matches the brief, but 15 GB upload and long pod starts slow every iteration.
- **D2 Small model only:** cheapest, but not "7B class" and no memory-tuning story on 24 GB.
- **D2 CPU inference to avoid the GPU quota:** quota is approved; CPU would not satisfy the GPU requirement.

## Consequences
**Positive**
- Low spend while iterating; platform proven separately from GPU issues.
- Fast, cheap iteration; swapping the model is a config change, so switching late is low risk.

**Negative**
- The top-graded item (`nvidia-smi` on a real GPU pod) comes late and must not be squeezed out.
- Mixed architecture (arm64 system, x86 GPU): images need the right platform (ADR-005).
- If the 7B run is skipped, the README must say the system was validated on a smaller model.
- Small-model numbers must not be reported as 7B results; each load test names its model.
- 7B needs its own `--max-model-len` and memory check (KV cache, OOM risk).
- Placeholder numbers are not LLM results.
