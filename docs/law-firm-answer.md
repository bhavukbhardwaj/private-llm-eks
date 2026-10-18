# What I would change before this serves a law firm's confidential documents

The PoC is private by design (no internet gateway, no NAT, internal ALB, IRSA, encrypted volumes). It is not ready for privileged client data. Four areas, then what else I would add.

## Encryption
- Dedicated customer-managed KMS keys per purpose (EBS, S3, ECR, EKS secrets, logs) with rotation and reviewed key policies, held in a separate security account. The PoC reuses one shared Identity Center key, and rotation is off.
- TLS everywhere: HTTPS on the ALB with a private certificate, and TLS between pods. The PoC uses plain HTTP inside the VPC.
- Never persist prompts or answers. Encrypt anything that must be stored (S3 SSE-KMS, endpoint policies that pin the bucket and key).

## Audit logging
- Turn on what the PoC switched off to save cost: EKS `api`, `audit` and `authenticator` logs, an organisation-wide CloudTrail (multi-region, log-file validation, data events on the document buckets), and VPC flow logs.
- Ship all logs to a separate log-archive account with S3 Object Lock, so operators cannot edit them.
- Add an application audit log per request: who, when, matter ID, document IDs and hashes, never the content. Alert on anomalies (GuardDuty).

## Access control
- Put authentication in front of the model: vLLM has none. Use SSO (OIDC) with MFA and per-matter authorisation (ABAC), so a lawyer reaches only their own matters.
- Least privilege everywhere: no AdministratorAccess at runtime, no shared roles, Kubernetes RBAC mapped to groups, break-glass access with approval and recording. People do not get shells on production nodes.
- Secrets in AWS Secrets Manager, rotated.

## Network isolation
- Its own AWS account and VPC. Keep the no-internet design, and add VPC endpoint policies, security-group rules that reference groups (not CIDRs), and default-deny Kubernetes NetworkPolicies.
- Dedicated nodes (or a cluster) per client or matter group, so workloads from different clients never share a node.
- Clients reach it over PrivateLink or a VPN, never the internet.

## Also
- Verify model weights and images (hashes, signed images, vulnerability scans) and pin them.
- Data retention and deletion policy, data-residency check, backups and disaster recovery across two AZs, a penetration test, and a data-processing agreement with the firm.
