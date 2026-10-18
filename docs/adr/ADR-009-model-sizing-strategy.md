# ADR-009: Model sizing (small model first, 7B for the final run)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-001](ADR-001-instance-type-and-capacity-model.md), [ADR-002](ADR-002-model-delivery-into-cluster.md), [task.md](../../task.md) section 2.3

## Context
- The brief asks for a 7B-class model on one A10G, weights in S3.
- What is graded is the platform end to end (GPU schedules, `nvidia-smi`, S3 via IRSA, probes, metrics), not model quality.
- Changing the model only changes `--model`, `--served-model-name`, `--max-model-len`, `--gpu-memory-utilization` and maybe dtype. Terraform, manifests, dashboard and load test stay the same.
- 7B fp16 is about 15 GB: S3 storage is about $0.35/month. Size costs time, not money.
- GPU hourly price does not depend on model size (ADR-001).

## Decision
- **Dev:** a small instruct model, Qwen2.5-0.5B-Instruct (about 1 GB), uploaded to S3 at a pinned revision.
- **Final demo:** a 7B-class model (Qwen2.5-7B-Instruct, pinned revision) on `g5.xlarge`, if time and budget allow. Same manifests; change only the arguments and S3 prefix.
- **Final system is GPU, not CPU-only.** The top criterion needs a real GPU pod.
- **CPU stage (optional):** vLLM CPU backend on Graviton, or a stub. A ready-made arm64 vLLM CPU image is **not verified**; building it is the fallback.
- Exact model, revision and vLLM arguments with reasons go in the README.

## Alternatives considered
- **7B from the start:** matches the brief, but slow iteration (15 GB upload, long pod start) and more GPU hours spent debugging.
- **Small model only:** cheapest, but not "7B class" and no memory-tuning story on 24 GB.
- **CPU inference to avoid GPU quota:** quota is now approved; it would not satisfy the GPU requirement and adds an image to build.

## Consequences
**Positive**
- Fast, cheap iteration; the final run still matches the brief.
- Swapping the model is a config change, so switching late is low risk.

**Negative**
- If the 7B run is skipped, the README must say the system was validated on a smaller model.
- Small-model performance numbers must not be reported as 7B results; each load test names its model.
- 7B needs its own `--max-model-len` and memory check (KV cache, OOM risk).
