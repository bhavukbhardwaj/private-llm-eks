# ADR-006: Private EKS API, reached through an SSM bastion

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-004](ADR-004-aws-authentication-sso.md), [ADR-011](ADR-011-logging-and-monitoring-defaults.md), [task.md](../../task.md) section 2.2

## Context
- No public ingress and no NAT for model traffic.
- `kubectl` and Helm need to reach the EKS API.
- The demo `curl` must run from inside the VPC.
- One operator, on a laptop with a changing IP.

## Decision
- **EKS API endpoint is private only.**
- **Bastion:** `t4g.micro` **Spot** in a private subnet, no public IP, no inbound rules, no SSH key.
- **Persistent Spot request, behaviour `stop`:** an interrupted bastion restarts and keeps its disk. On-Demand is the unused fallback (about $0.0084/hr).
- **Access:** Session Manager, from the EC2 console (browser) or the CLI.
- **IAM:** `AmazonSSMManagedInstanceCore` plus an EKS access entry with cluster admin.
- **Network:** bastion SG may reach the API on 443 only. Egress is limited to the VPC and S3.
- **Endpoints:** `ssm`, `ssmmessages`, `ec2messages` in one AZ, created only for working sessions.
- **No internet on the bastion:** kubectl, helm and manifests come from the S3 tools bucket.
- **Terraform (AWS resources) runs from the laptop.** Helm and kubectl run on the bastion.
- **Demo `curl`:** run from the bastion and from a client pod.

**Viewing Grafana (two chained port-forwards, nothing public):**
- On the bastion: `kubectl -n monitoring port-forward svc/grafana 3000:80 --address 127.0.0.1`
- On the laptop: `aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'`
- Open `http://localhost:3000`. Admin password comes from the cluster secret, never from git.
- Needs `session-manager-plugin` on the laptop (install needs `sudo`).

## Alternatives considered
- **Public endpoint limited to my IP /32:** free and simple, but leaves a public control-plane address. Documented fallback.
- **Public-subnet bastion with SSH:** internet-facing host, key pair, changing-IP rule. Rejected.
- **Client VPN or Direct Connect:** about $70+/month. Disproportionate.
- **Public endpoint open to 0.0.0.0/0:** not acceptable.
- **Internal ALB for Grafana:** about $0.03/hr more for no gain.

## Consequences
**Positive**
- Nothing in the account is publicly reachable: no inbound ports, no SSH keys, IAM-authenticated sessions.
- The required in-VPC `curl` is natural from the bastion.

**Negative**
- 3 SSM endpoints cost about $0.03/hr (about $0.72/day) while they exist. Destroy when idle.
- No internet on the bastion, so tools and manifests are staged through S3.
- Terraform's kubernetes and helm providers cannot reach the private API from the laptop.
- A Spot interruption drops the open session until the instance restarts.
- Browser Session Manager cannot forward ports, so Grafana needs the CLI plugin.
