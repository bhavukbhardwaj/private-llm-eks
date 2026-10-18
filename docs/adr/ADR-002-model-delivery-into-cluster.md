# ADR-002: Model delivery (init container syncing from S3)

- **Status:** Accepted (2026-10-18). Timings are estimates until measured.
- **Related:** [ADR-003](ADR-003-image-supply-without-nat.md), [ADR-009](ADR-009-model-sizing-strategy.md)

## Context
- Weights must come from our S3 bucket, not the internet at pod start.
- Nodes have no NAT; S3 is reached through the free gateway endpoint.
- Two options: init container sync to `emptyDir`, or bake weights into the image.
- Sizes: Qwen2.5-0.5B about 1 GB, Qwen2.5-7B bf16 about 15 GB, vLLM image 9.04 GB compressed.
- GPU node root volume is gp3 60 GB.

## Decision
- **Init container syncs S3 to an `emptyDir`**, mounted read-only by vLLM.
- **S3 layout:** `s3://<models-bucket>/<model>/<revision-sha>/`. Revision is the pinned Hugging Face commit.
- **Init image:** the mirrored `aws-cli` image from ECR.
- **Access:** dedicated service account with IRSA, only `s3:GetObject` and `s3:ListBucket` on that bucket.
- **Start gate:** vLLM starts only after `aws s3 sync` exits 0.
- Current dev model: Qwen2.5-0.5B-Instruct at revision `7ae557604adf67be50417f59c2c2f167def9a775`.

## Alternatives considered
- **Bake weights into the image:** about 25 GB for 7B, about $2.50/month ECR per version, a rebuild for every model change, and a cold pull plus unpack that is tight on 60 GB.
- **Mountpoint for S3 (CSI):** no copy, but weights load over a network filesystem and a driver must be run and mirrored.
- **Download from Hugging Face at start:** forbidden by the brief, and there is no internet.
- **Pre-filled EBS/EFS volume:** faster restart, but EBS is AZ-bound and EFS adds cost and latency.

## Consequences
**Positive**
- Serving image stays small; the model is not copied into every image version.
- Rollback is a prefix change plus a pod restart, with no rebuild. Bucket versioning guards bad uploads.
- Least privilege through IRSA, and no model bytes in ECR.
- Switching 0.5B to 7B is a config change.

**Negative**
- Every pod start re-downloads: under 30 s for 1 GB, about 2 to 4 min for 15 GB, plus 1 to 2 min vLLM load.
- Probes need a startup probe or a long initial delay.
- `emptyDir` uses node disk, so the volume must hold weights plus image layers.
- Depends on S3 and the gateway endpoint; IAM mistakes block the pod at init.
- A Spot interruption means a fresh download.
