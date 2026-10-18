# What I would change before this serves a law firm's confidential documents

The PoC is private by design (no internet gateway or NAT, internal ALB, IRSA, encrypted disks), but it is not ready for privileged client data.

**Encryption.** Use dedicated customer-managed KMS keys per purpose (disks, S3, ECR, logs), with rotation and reviewed key policies, held in a separate security account. The PoC reuses one shared key with rotation off. Add TLS everywhere: HTTPS on the ALB and between pods (the PoC uses plain HTTP inside the VPC). Never store prompts or answers.

**Audit logging.** Turn on what the PoC switched off to save cost: EKS `api`, `audit` and `authenticator` logs, an organisation CloudTrail with log validation and data events on the document buckets, and VPC flow logs. Send them to a separate log-archive account with S3 Object Lock so operators cannot alter them. Add a per-request application log (who, when, matter and document IDs, never the content) and alert on anomalies.

**Access control.** The model server has no authentication. Put a gateway in front with SSO, MFA and per-matter authorisation, so lawyers reach only their own matters. Apply least privilege: no AdministratorAccess at runtime, Kubernetes RBAC mapped to groups, secrets in Secrets Manager, and approved break-glass access. Nobody gets a shell on production nodes.

**Network isolation.** Use its own AWS account and VPC, and keep the no-internet design. Add VPC endpoint policies, security groups that reference groups instead of CIDRs, and default-deny network policies. Give each client group dedicated nodes, and let clients connect only over PrivateLink or VPN.

**Also:** signed and scanned images and weights, a retention and deletion policy, disaster recovery across two AZs, a penetration test, and a data-processing agreement.
