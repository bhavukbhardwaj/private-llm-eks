# ADR-003: Image supply without internet: mirror upstream images into private ECR with crane

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [ADR-008](ADR-008-cost-optimisation-choices.md), [task.md](../../task.md) section 2.2

## Context

There is no NAT gateway and no internet gateway, so nodes cannot pull from Docker Hub, GHCR, Quay or registry.k8s.io. Every image the cluster runs must be pulled from private ECR through the ECR interface endpoints and the S3 gateway endpoint (ECR layers are stored in S3). The cluster is mixed-architecture: system nodes are arm64 (Graviton) and the GPU node is x86_64.

## Decision

1. Create one private ECR repository per image in the `foundation` stack (immutable tags, scan on push, keep last 5 images).
2. A script in `scripts/` copies each pinned upstream image into ECR with **`crane copy`**, which copies the multi-arch manifest and all layers without pulling to a local Docker daemon. Images are referenced by tag and recorded with digest in the repo.
3. Helm values and manifests reference only the ECR URLs. Public registries are never used at runtime.
4. Images needed: vLLM, AWS CLI (init container), NVIDIA device plugin, DCGM exporter, AWS Load Balancer Controller, EBS CSI driver add-on images if not provided by the EKS add-on, Prometheus stack components, Grafana, Loki, Promtail, busybox and the load-test image.

## Alternatives considered

- **ECR pull-through cache rules.** Convenient, but the first pull needs the upstream registry reachable from ECR (works from the AWS side, not the node), and it needs credentials for some registries. It also adds rules and behaviour to explain; explicit mirroring is simpler to audit.
- **NAT gateway for the first pull.** About $0.045 per hour plus data processing and explicitly against the brief for model traffic.
- **docker pull / push from the laptop.** Works but pulls the local architecture only unless carefully done, and downloads several GB locally; crane copies registry to registry.

## Consequences

Positive
- No internet path at runtime; reproducible, pinned and scannable images.
- Multi-arch manifests keep arm64 and x86 nodes working from the same tag.
- Empty or small repos cost almost nothing (storage about $0.10 per GB-month).

Negative / risks
- Extra manual step before first deploy and for every version bump; the script must be kept in sync with Helm chart image lists.
- Some charts hard-code registries or init images; values must be checked for stray public references or pods will sit in `ImagePullBackOff`.
- Mirroring needs working AWS credentials and the ECR repositories applied first.
- Large images (vLLM several GB) take time and bandwidth to copy from the laptop; copy from an in-region machine if it is too slow.
