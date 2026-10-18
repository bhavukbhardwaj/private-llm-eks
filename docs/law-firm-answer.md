# What I would change before this serves a law firm's confidential documents

The PoC is private by design (no internet gateway, no NAT, internal ALB, IRSA, encrypted volumes), but not ready for privileged client data.

**Encryption**
- Dedicated customer-managed KMS keys per purpose (EBS, S3, ECR, logs) with rotation and reviewed policies, in a separate security account. The PoC reuses one shared key with rotation off.
- TLS everywhere: HTTPS on the ALB and between pods. The PoC uses plain HTTP inside the VPC.
- Never persist prompts or answers; encrypt anything stored with KMS.

**Audit logging**
- Turn on what the PoC switched off for cost: EKS `api`, `audit` and `authenticator` logs, an organisation CloudTrail (log validation, data events on document buckets) and VPC flow logs.
- Ship them to a separate log-archive account with S3 Object Lock, so operators cannot alter them.
- Add a per-request application log: who, when, matter and document IDs, never the content.

**Access control**
- Put authentication in front of vLLM (it has none): SSO with MFA and per-matter authorisation, so lawyers reach only their own matters.
- Least privilege: no AdministratorAccess at runtime, Kubernetes RBAC mapped to groups, break-glass access with approval, no shells on production nodes. Secrets in Secrets Manager.

**Network isolation**
- Its own AWS account and VPC. Keep the no-internet design; add VPC endpoint policies, security groups that reference groups, and default-deny NetworkPolicies.
- Dedicated nodes per client group, and clients connect over PrivateLink or VPN.

**Also:** verified and signed images and weights, a retention and deletion policy, disaster recovery across two AZs, a penetration test, and a data-processing agreement.
