# ADR-009: Model sizing strategy (small model for development, 7B for the final run)

- **Status:** Proposed (2026-10-18)
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), ADR-002 (model delivery, to be written), [task.md](../../task.md) section 2.3

## Context

The brief asks for a 7B-class open-weight model on one A10G, with weights stored in S3. The graded point is that the platform works end to end (GPU schedules, `nvidia-smi` evidence, S3 load via IRSA, probes, metrics), not model quality. Model choice changes only configuration: `--model`, `--served-model-name`, `--max-model-len`, `--gpu-memory-utilization`, and possibly dtype or quantisation flags; the Terraform, manifests, dashboards and load test are identical. A 7B fp16 model is about 15 GB; storage in S3 is about $0.35/month, so size is a time cost (upload, init-container sync, load into GPU), not a money cost.

## Decision (proposed)

1. Build and debug with a **small instruct model** (for example Qwen2.5-0.5B or 1.5B-Instruct, 1 to 3 GB) on the cheapest available GPU Spot instance. Fast sync, fast start, low cost.
2. For the final demo and recorded evidence, switch to a **7B-class model** (for example Qwen2.5-7B-Instruct, pinned revision) on g5.xlarge, if quota, time and budget allow. Keep the same manifests; change only the model arguments and the bucket prefix.
3. A CPU-only model server is **not** used for the final system. The assessment's top criterion requires a real GPU workload (`nvidia-smi`). During the skeleton phase, a placeholder service on Graviton stands in (ADR-000).
4. The exact model, revision hash, and chosen vLLM arguments with reasons are recorded in ADR-002 and the README.

## Alternatives considered

- **7B only from the start.** Closest to the brief, but slows every iteration (15 GB upload, longer pod start) and costs more GPU hours while debugging.
- **Small model only.** Cheapest, but deviates from the stated "7B class" and from the brief's sizing discussion (`--max-model-len`, memory utilisation on 24 GB).
- **CPU inference (vLLM CPU backend or llama.cpp) to avoid GPU quota.** Would unblock early work but does not satisfy the GPU requirement and adds a separate image to build and mirror.

## Consequences

Positive
- Faster, cheaper iteration; the final run still matches the brief.
- Model swap is a config change, so the risk of switching at the end is low.

Negative / risks
- If the final 7B run is skipped for time or quota reasons, the README must say the system was validated with a smaller model.
- Performance numbers from the small model must not be reported as 7B results; load-test results must name the model used.
- Memory behaviour (KV cache sizing, OOM risk) differs on 7B; the final run needs its own `--max-model-len` and `--gpu-memory-utilization` check.
