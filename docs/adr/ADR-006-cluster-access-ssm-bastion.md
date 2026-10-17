# ADR-006: Private EKS API endpoint, accessed through an SSM-managed bastion

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [ADR-004](ADR-004-aws-authentication-sso.md), [task.md](../../task.md) section 2.2

## Context

The brief requires no public ingress to the model and no NAT for model traffic. The EKS API server needs a reachable endpoint for `kubectl`, Helm and applying manifests. The `curl` in the demo must come from inside the VPC. A personal sandbox has one operator working from a laptop with a changing IP.

## Decision

1. EKS API endpoint: **private only** (public endpoint disabled).
2. Operator access through a small **EC2 bastion in a private subnet** with **no public IP, no inbound security-group rules, no SSH key**. Access is by **AWS Systems Manager Session Manager**, either from the EC2 console (browser: Connect > Session Manager) or the CLI plugin.
3. The bastion's IAM role has `AmazonSSMManagedInstanceCore` plus a mapped EKS access entry for cluster admin. Its SG may reach the cluster API on 443 only.
4. VPC interface endpoints `ssm`, `ssmmessages` and `ec2messages` are added to the existing endpoint set, **in a single AZ** (the bastion's AZ) to limit cost. They are created for working sessions and destroyed with the rest of the endpoints.
5. The bastion has no internet. Tooling comes from AL2023 repos (served from S3 via the free S3 gateway endpoint) and from our own S3 tools bucket (kubectl, helm, repo manifests synced from the laptop with `aws s3 sync`). Kubernetes/Helm resources are applied from the bastion; Terraform for AWS resources runs from the laptop.
6. The in-VPC demo `curl` is run from the bastion, and also from a client pod.
7. Instance: `t4g.micro` (arm64, matches ADR-000) on **Spot** (operator decision, 2026-10-18; amended from the initial On-Demand proposal). Use a persistent Spot request with interruption behaviour `stop`, so an interrupted bastion stops and restarts instead of being terminated; EBS (encrypted) and the tools stay in place. Fallback: switch to On-Demand if interruptions become disruptive (about $0.0084/hr).

## Alternatives considered

- **Public API endpoint restricted to operator IP /32.** Free and simplest, but leaves a public control-plane address, needs updating when the IP changes. Kept as the documented fallback if the bastion path blocks progress.
- **Bastion in a public subnet with SSH from my IP.** Works without SSM endpoints, but puts an internet-facing host, a key pair and a changing-IP rule in the design. Rejected.
- **Client VPN / Direct Connect.** Roughly $70+/month; disproportionate here.
- **Public endpoint open to 0.0.0.0/0.** Not acceptable.

## Consequences

Positive
- Nothing in the account is publicly reachable (matches the law-firm story: private control plane, no inbound ports, no SSH keys, sessions are IAM-authenticated and loggable).
- Browser access means no local plugin or kubeconfig tunnelling.
- The required in-VPC `curl` is natural from the bastion.

Negative / risks
- Extra cost: 3 interface endpoints in one AZ, about $0.03/hr (about $22/month if left up, roughly $0.72/day) plus a few tenths of a cent per hour for the Spot bastion (verify the live price when applying). Destroy when idle.
- Extra work: no internet on the bastion, so tools and manifests must be staged through S3; Terraform's kubernetes/helm providers cannot be used from the laptop (cluster is private), so cluster add-ons are installed with CLI/Helm from the bastion.
- Spot interruptions can drop an open session; the instance stops and must restart (or a new request must be fulfilled) before reconnecting. Acceptable for a sandbox.
- Single-AZ endpoint choice is a sandbox cost saving, a known availability limitation.
- Session Manager session logging to CloudWatch/S3 is optional; not enabled by default (ties to ADR-005).
