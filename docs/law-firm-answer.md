# What I would change before this serves a law firm's confidential documents

The PoC is private by design (no internet gateway, no NAT, an internal ALB, IRSA, encrypted node disks), but it is not ready for privileged client data. I would change four things first.

**Encryption.** Use dedicated customer-managed KMS keys per purpose (disks, S3, ECR, logs) with rotation and reviewed key policies, held in a separate security account. The PoC reuses one shared key whose rotation is off. Add TLS everywhere: HTTPS on the ALB with a private certificate, and TLS between pods, because the PoC uses plain HTTP inside the VPC. Never persist prompts or answers, and encrypt anything that must be stored with KMS and bucket policies that pin the key.

**Audit logging.** Turn on what the PoC switched off to save cost: the EKS `api`, `audit` and `authenticator` logs, an organisation-wide CloudTrail with log-file validation and data events on the document buckets, and VPC flow logs. Ship all of it to a separate log-archive account with S3 Object Lock, so no operator can alter or delete a record. Add an application log for every request that records who asked, when, the matter and document IDs, and never the content, and alert on anomalies.

**Access control.** The model server has no authentication today. Put an authenticating gateway in front of it, with SSO and MFA, and authorise each lawyer per matter, so people can only reach the matters they are assigned to. Apply least privilege everywhere: no AdministratorAccess at runtime, Kubernetes RBAC mapped to groups, secrets in Secrets Manager, and a break-glass path with approval and recording. Nobody gets a shell on a production node.

**Network isolation.** Run it in its own AWS account and VPC, and keep the no-internet design. Add VPC endpoint policies, security groups that reference other groups instead of CIDR ranges, and default-deny Kubernetes NetworkPolicies. Give each client group dedicated nodes, so workloads from different clients never share a machine. Clients connect over PrivateLink or a VPN, never the internet.

**Also:** verify and sign images and model weights, set a retention and deletion policy, add backups and recovery across two AZs, run a penetration test, and sign a data-processing agreement with the firm.
