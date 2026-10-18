# ADR-003: Image supply without internet (crane copy into private ECR)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [ADR-002](ADR-002-model-delivery-into-cluster.md)

## Context
- No NAT and no internet gateway, so nodes cannot pull from Docker Hub, quay, nvcr or registry.k8s.io.
- All images must come from private ECR via the ECR endpoints (layers come through the S3 gateway endpoint).
- Mixed architecture: arm64 system nodes, x86_64 GPU node.

## Decision
- One private ECR repo per image, in the `foundation` stack (immutable tags, scan on push, keep last 5).
- **Copy third-party images with `crane copy`. Never `docker pull` then `docker push`.**
- `crane copy` streams registry to registry, keeps the digest, and needs no Docker daemon.
- **Platform per image:**
  - `linux/arm64` for system-node images (LB controller, Prometheus stack, Grafana, Loki).
  - `linux/amd64` for GPU-node images (vLLM, NVIDIA device plugin, DCGM exporter).
  - All platforms for images used on both (busybox, node-exporter, aws-cli).
- **Only our own image is built:** the load-test client, with `docker buildx build --platform linux/arm64 --push`.
- List and pinned tags live in `scripts/images.txt`. `scripts/mirror-images.sh` supports `--dry-run` and `ONLY=`, and skips tags already present.
- Manifests and Helm values use ECR URLs only.

## Alternatives considered
- **ECR pull-through cache:** needs upstream credentials for some registries and hides what is pinned.
- **NAT gateway for the first pull:** about $0.045/hr plus data, and against the brief.
- **`docker pull/push` from the laptop:** fetches only the laptop architecture (arm64) and breaks the x86 GPU node.

## Consequences
**Positive**
- No internet path at runtime.
- Pinned, scannable, reproducible images.
- Multi-arch tags work on both node types.
- Storage cost is about $0.10 per GB-month.

**Negative**
- A manual mirror step before deploy and on every version bump.
- Some Helm charts hard-code registries or init images; check values for stray public references.
- Large images (vLLM 9.04 GB) depend on laptop bandwidth (about 30 min at 40 Mbit/s).
- Needs AWS credentials and the ECR repos applied first.
