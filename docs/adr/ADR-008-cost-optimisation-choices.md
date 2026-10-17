# ADR-008: Cost optimisation choices (Spot, free S3 endpoint, default encryption keys, single working AZ)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [ADR-006](ADR-006-cluster-access-ssm-bastion.md), [ADR-007](ADR-007-terraform-structure-and-state.md), [task.md](../../task.md) sections 2.2 and 5. ADR-001 (instance type and capacity) will carry the final per-hour and per-month numbers.

## Context

Total budget is USD 150 (personal alerts are set lower). The stack is built, used and destroyed repeatedly, and the main costs are hourly: EKS control plane ($0.10/hr), interface endpoints (about $0.01/hr per AZ each), GPU nodes, bastion. Cross-AZ data transfer is charged ($0.01/GB each way).

## Decision

1. **Spot capacity** for the system nodes (Graviton), the bastion (t4g.micro) and the GPU node, with On-Demand as a documented fallback.
2. **S3 gateway VPC endpoint** (free) for ECR layer pulls, tools and model weights. Interface endpoints are created only in `platform` and destroyed when idle.
3. **Default (AWS-managed) encryption instead of a customer-managed KMS key, for the sandbox:**
   - EBS: account-default encryption with the AWS-managed `aws/ebs` key; node volumes are encrypted.
   - S3 buckets: default SSE-S3 (or the AWS-managed `aws/s3` key), public access blocked, TLS-only bucket policies.
   - EKS secrets: the EKS default encryption at rest (no envelope encryption with our own key).
   - The `kms` interface endpoint is still created, as the brief lists it.
   - The Terraform code keeps a `kms` module and a `use_cmk` variable (default `false`). Setting it to `true` creates a customer-managed key (about $1/month) and switches EBS, S3 and EKS secrets to it, so the production-grade setup is a one-variable change.
4. **Single working AZ.** Two private subnets are created in two AZs (EKS and the internal ALB require subnets in at least two AZs), but nodes, the bastion, the SSM and other interface endpoints, and all pods are placed in one primary AZ (variable `primary_az`) so traffic does not cross AZs. The AZ is chosen by checking which AZ offers the needed instance types (system, g5 or equivalent) with good Spot price.
5. No NAT gateway at all (also a cost saving, about $0.045/hr plus data) and no internet gateway.

## Alternatives considered

- **Customer-managed KMS key from day one.** Matches the brief literally and is better practice (key policy, rotation control, audit through CloudTrail), costing about $1/month plus request fees. Deferred, not rejected: kept as a toggle and as a final-polish step.
- **All resources spread over two AZs.** Resilient but doubles interface-endpoint cost and adds cross-AZ transfer; not needed for a single-replica sandbox.
- **On-Demand everywhere.** Predictable, but roughly 2 to 3 times the price for the GPU node.

## Consequences

Positive
- Hourly baseline stays small, and teardown is simple; cross-AZ transfer charges are close to zero.
- Encryption at rest is still on everywhere.

Negative / risks
- **Deviation from brief 2.2** ("Encrypt EBS volumes used by nodes with a customer-managed KMS key") unless `use_cmk=true` is flipped before submission. Plan: flip and apply once near the end, to be able to show the CMK path. If not done, the README must state the deviation plainly.
- AWS-managed keys cannot have a custom policy, are not individually disable-able, and give less control over audit and revocation.
- Single working AZ means no AZ resilience: an AZ outage or Spot capacity shortage in that AZ stops the system. Single-AZ GPU Spot also narrows the capacity pool; fall back to another AZ or On-Demand if Spot is unavailable.
- The internal ALB still has load balancer nodes in both AZs, so a small amount of cross-AZ traffic (ALB node to pod) can occur; negligible at load-test volume.
- Spot interruptions can disrupt demos; record evidence early.
