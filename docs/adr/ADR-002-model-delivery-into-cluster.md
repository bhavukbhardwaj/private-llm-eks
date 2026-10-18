# ADR-002: Model delivery (init container syncing from S3)

- **Status:** Accepted (2026-10-18)

## Context
- Weights must come from our S3 bucket, not the internet. Nodes have no internet; S3 is reached through the free gateway endpoint.
- Qwen2.5-7B-Instruct is 15.2 GB (4 files). The vLLM image is 9.04 GB. GPU node disk is 60 GB.

## Decision
- An **init container copies the model from S3 into an `emptyDir`** that vLLM mounts read-only.
- S3 path: `<bucket>/<model>/<revision>/`, with the Hugging Face commit pinned (`a09a354…` for 7B).
- The pod uses a service account with **IRSA**: `s3:GetObject` and `s3:ListBucket` on the models bucket only.
- vLLM starts only after the sync succeeds.

## Alternatives considered
- **Bake weights into the image:** about 25 GB per version (about $2.50/month in ECR), a rebuild per model, and a cold pull that is tight on 60 GB.
- **Mountpoint for S3 (CSI):** no copy, but an extra driver and slower loading.
- **Download from Hugging Face at start:** not allowed, and there is no internet.
- **EBS or EFS volume with weights:** faster restarts, but AZ-bound (EBS) or costly (EFS).

## Consequences
**Positive**
- Small serving image; the model is not copied into every image version.
- Rollback is a path change and a pod restart, with no rebuild.
- Least privilege through IRSA; no model bytes in ECR.

**Negative**
- Every pod start downloads the weights: about 3 to 5 minutes for 15 GB, plus 2 to 3 minutes for vLLM to load. The startup probe allows 15 minutes.
- The `emptyDir` uses node disk (15 GB of 60 GB).
- Depends on S3 and the gateway endpoint being reachable.
