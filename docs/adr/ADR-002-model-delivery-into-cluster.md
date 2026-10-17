# ADR-002: Model delivery into the cluster (init container syncing from S3, not a baked image)

- **Status:** Accepted (2026-10-18). Timing figures are estimates to be replaced with measured values.
- **Related:** [ADR-009](ADR-009-model-sizing-strategy.md), [ADR-003](ADR-003-image-supply-without-nat.md), [task.md](../../task.md) section 2.3

## Context

vLLM must load weights from an S3 bucket we create, not from the public internet at pod start. Nodes have no NAT and no internet; S3 is reachable through the free gateway endpoint. Two ways to get weights into the pod: an init container that syncs from S3 to an `emptyDir`, or baking the weights into the container image.

Rough sizes: Qwen2.5-0.5B-Instruct about 1 GB; Qwen2.5-7B-Instruct bf16 about 15 GB. The vLLM serving image is several GB (to be measured after mirroring). GPU node root volume is gp3 60 GB.

## Decision

Use an **init container that syncs the model from S3 into an `emptyDir`**, mounted read-only by the vLLM container.
- S3 layout: `s3://<models bucket>/<model-name>/<revision>/...`, where `<revision>` is the pinned Hugging Face commit hash. The pod gets the prefix through an environment variable.
- The init container uses the AWS CLI image mirrored in ECR and a **dedicated service account with IRSA**, allowing only `s3:GetObject` and `s3:ListBucket` on that bucket and prefix.
- A completion marker file and `aws s3 sync` exit code gate the main container; vLLM starts with `--model` pointing to the local path.
- The model prefix, the vLLM args and the revision hash are recorded in the README and the manifest.

## Alternatives considered

- **Bake weights into the image.** No S3 access at runtime and one artifact to pull, but the image becomes about 25 GB for the 7B model (about 9 GB of runtime plus 15 GB of weights), ECR storage grows by roughly $0.10 per GB-month per version (about $2.50 per month per 7B image), every model change needs a rebuild and push of a 25 GB image, and a cold node needs the full 25 GB pull plus about the same free disk to unpack, which is tight on a 60 GB root volume.
- **Mount from S3 with a CSI driver (Mountpoint for S3).** Avoids the copy, but loads weights over a network filesystem at start and adds a driver to run, mirror and secure; unnecessary for one replica.
- **Download from Hugging Face at start.** Forbidden by the brief and impossible without internet.
- **EBS or EFS volume pre-populated with weights.** Faster restarts, but EBS is AZ-bound and adds a volume to manage and pay for; EFS adds cost and latency. Not worth it for the sandbox.

## Consequences

Positive
- **Image size:** the serving image stays small (runtime only); the model is not duplicated per image version.
- **Versioning and rollback:** each revision is an S3 prefix; roll forward or back by changing the prefix variable and restarting the pod, with no rebuild. Bucket versioning protects against a bad overwrite.
- **Least privilege and auditability:** access is a scoped IRSA role; no model bytes in ECR.
- Switching the model (0.5B for dev, 7B for the final run) is a config change (ADR-009).

Negative / risks
- **Startup time:** every pod start re-downloads the weights. Estimate: 1 GB in under 30 seconds; 15 GB in roughly 2 to 4 minutes over the S3 gateway endpoint, plus 1 to 2 minutes of vLLM load and CUDA graph capture. Readiness probes and `initialDelaySeconds` or a startup probe must allow for this. A baked image would still pay for a cold image pull on a new node.
- The `emptyDir` lives on the node disk, so the root volume must hold the full model plus the image layers (hence 60 GB for the 7B run).
- Runtime dependency on S3 and the gateway endpoint being available; an S3 or IAM misconfiguration blocks the pod at init (an easy failure to see in pod events).
- Spot interruption means a fresh node and a fresh download.
