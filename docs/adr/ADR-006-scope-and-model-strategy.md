# ADR-006: Build order and model (platform first, then GPU; 7B model)

- **Status:** Accepted (2026-10-18)

## Context
- The brief mixes platform work with GPU and model work. The GPU part is the costly one, and the quota request took hours.
- What is graded is the platform end to end. A model change only changes a few vLLM arguments.

## Decision
- **Platform first:** state, VPC, endpoints, EKS, IRSA, load balancer controller and an internal ALB with a placeholder app. **Then GPU:** device plugin, `nvidia-smi`, vLLM, DCGM, monitoring and the load test.
- **Models:** Qwen2.5-0.5B-Instruct for the first run (1 GB, quick to load). **Qwen2.5-7B-Instruct for the final system** (the brief's size; pinned revision `a09a354…`, Apache-2.0).
- 7B in fp16 is 15.2 GB. On the 24 GB A10G, `--gpu-memory-utilization 0.90` leaves about 5 GiB for the KV cache, enough for `--max-model-len 8192`.
- The GPU must be real: no CPU-only serving.

## Alternatives considered
- **GPU first:** costly debugging, and platform and GPU bugs mix.
- **0.5B only:** cheap, but not the brief's 7B class.
- **7B from the start:** a 15 GB upload and slow starts while debugging.

## Consequences
**Positive**
- Platform bugs were found and fixed on cheap nodes before the GPU was running.
- Swapping the model took only a config change and one upload.

**Negative**
- The top-graded proof (`nvidia-smi` on a GPU pod) came late.
- 0.5B and 7B numbers are not comparable; each result names its model.
- The 7B model needs more GPU memory and takes longer to load.
