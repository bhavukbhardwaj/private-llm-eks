# ADR-005: Delivery and Terraform (stacks, state, images, monitoring)

- **Status:** Accepted (2026-10-18)

## Context
- Some things are cheap but slow to recreate (weights, images); others bill hourly (EKS, nodes, endpoints).
- Nodes have no internet, so they cannot pull from Docker Hub, quay or nvcr. System nodes are arm64; the GPU node is x86_64.

## Decision
**Three Terraform stacks**
- `bootstrap`: state bucket. `foundation` (persistent): VPC, S3 endpoint, ECR, buckets. `platform` (disposable): endpoints, EKS, nodes, bastion, IRSA.
- `platform` reads `foundation` through remote state. Destroying `platform` stops the hourly bill.
- Kubernetes objects are applied from the bastion, not by Terraform (the API is private).

**State and versions**
- S3 state with **native locking (`use_lockfile`), no DynamoDB** (generally available since Terraform 1.11).
- Terraform `>= 1.11` (installed 1.16.6), AWS provider `~> 6.0`, lock file committed. Tags from provider `default_tags`.
- Every stack uses the same files: `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf` (+ `backend.tf`). One-line comment above every block. The EKS module is hand-written.

**Images**
- One private ECR repo per image. Copy with **`crane copy`**, never `docker pull` and `push`: it needs no Docker, keeps digests, and copies the right architecture (`arm64` for system nodes, `amd64` for the GPU node).
- Only our load-test image is built (`docker buildx`, arm64). Big images are copied from AWS CloudShell (vLLM: about 1 minute, against 30+ minutes from a laptop).

**Monitoring**
- Plain Prometheus scrapes pods annotated `prometheus.io/scrape` (vLLM, DCGM). Grafana loads the dashboard JSON by provisioning. No Prometheus Operator, so no ServiceMonitor (the brief allows an equivalent scrape config).

## Alternatives considered
- **One stack:** a destroy could also wipe weights and images.
- **S3 plus DynamoDB locking:** adds a table and uses the deprecated path.
- **Community EKS module:** less code, but opaque.
- **`docker pull` and `push`:** pulls only the laptop architecture (arm64) and breaks the GPU node.
- **kube-prometheus-stack:** more images, CRDs and pods on two small nodes.

## Consequences
**Positive**
- Cheap destroy and rebuild; small blast radius per apply.
- Pinned, private, multi-arch images; no internet path at runtime.

**Negative**
- Apply foundation first, destroy platform first.
- A manual mirror step for every new image version.
- No alert rules; Prometheus keeps 6 hours of data in an `emptyDir`.
- The `bootstrap` local state file must be kept to destroy the state bucket.
