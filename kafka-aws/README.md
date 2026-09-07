# Kafka + Keycloak + Kafka UI on AWS — Terraform + AWS CLI

One private EC2 box runs the Docker stack from the earlier tutorial. The **only public entry point** is an Application Load Balancer with an HTTPS certificate; Route 53 gives you two friendly URLs.

```
                 Internet
                     │
       ┌─────────────▼──────────────┐
       │  Route 53 hosted zone      │  keycloak.example.com ─┐
       │  (example.com)             │  kafka.example.com    ─┤ A (alias)
       └────────────────────────────┘                        │
                                                             ▼
 ┌─────────────────────────── VPC 10.0.0.0/16 ───────────────────────────┐
 │  PUBLIC subnets (2 AZs)                                               │
 │   ┌───────────────┐   ┌──────────────────────────────┐                │
 │   │ Internet GW   │   │ ALB :443 (ACM cert) :80→443  │ ◄── the ONE   │
 │   └───────┬───────┘   │  host keycloak.* → :8080     │     public    │
 │           │           │  host kafka.*    → :8090     │     door      │
 │   ┌───────┴───────┐   └──────────────┬───────────────┘                │
 │   │ NAT Gateway   │                  │                                │
 │   └───────┬───────┘                  │ (security group: ALB only)     │
 │  PRIVATE subnets (2 AZs)             ▼                                │
 │           │  outbound only  ┌──────────────────────────────┐          │
 │           └────────────────►│ EC2 t3.medium (no public IP) │          │
 │                             │  docker compose:             │          │
 │                             │   kafka  keycloak  kafka-ui  │          │
 │                             │  managed via SSM (no SSH)    │          │
 │                             └──────────────────────────────┘          │
 └───────────────────────────────────────────────────────────────────────┘
```

## Files

```
kafka-aws/
├── terraform/
│   ├── versions.tf              provider + default tags
│   ├── variables.tf             inputs (domain, passwords, size)
│   ├── network.tf               VPC, subnets, IGW, NAT, route tables, security groups
│   ├── dns.tf                   hosted zone, ACM certificate, A records
│   ├── alb.tf                   load balancer, listeners, host rules, target groups
│   ├── ec2.tf                   IAM role (SSM), private instance, cloud-init
│   ├── user_data.sh.tftpl       installs Docker and writes the compose stack
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── scripts/
    ├── create.sh                two-phase create (zone → delegate NS → everything)
    ├── destroy.sh               terraform destroy + AWS CLI leftover check
    ├── status.sh                instance, target health, container list (via SSM)
    └── cost.sh                  fixed estimate + real month-to-date spend (Cost Explorer)
```

## Step-by-step

**Prerequisites:** `aws` CLI (configured, `aws sts get-caller-identity` works), `terraform` ≥ 1.6, `jq`, `dig`, and a domain you own.

1. **Configure**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   nano terraform.tfvars        # domain_name + 4 passwords (make them long)
   ```
2. **Create** — the script creates the hosted zone first, prints 4 name servers, and waits until you set them at your registrar. Then it builds the rest (5–10 min) and waits for both ALB targets to be healthy (another 5–8 min while the box installs Docker and pulls images).
   ```bash
   ../scripts/create.sh
   ```
   If the domain is already delegated to this zone (e.g. second run): `../scripts/create.sh --skip-ns`.
3. **Use**
   * `https://kafka.<domain>` → click **Keycloak** → `alice` / `alice_password` (admin) or `bob` / `bob_password` (read-only)
   * `https://keycloak.<domain>` → Administration Console → `admin` / `keycloak_admin_password`
4. **Check on it**
   ```bash
   ../scripts/status.sh
   aws ssm start-session --target $(terraform output -raw instance_id)    # a shell on the box
   sudo docker compose -f /opt/kafka-stack/docker-compose.yml logs -f kafka-ui
   ```
5. **See what it costs**
   ```bash
   ../scripts/cost.sh
   ```
6. **Destroy** (everything, including data and the hosted zone)
   ```bash
   ../scripts/destroy.sh
   ```

## Cost

Approximate, **us-east-1, on-demand, running 24 × 7**. Prices drift; confirm with the [AWS Pricing Calculator](https://calculator.aws).

| Resource | Rate | Per month |
|---|---|---|
| EC2 `t3.medium` (2 vCPU, 4 GB) | $0.0416 / h | **$30.40** |
| EBS gp3 root volume, 30 GB | $0.08 / GB | **$2.40** |
| NAT Gateway | $0.045 / h + $0.045 / GB | **$32.85** + traffic |
| Application Load Balancer | $0.0225 / h + LCU | **$16.40** + ~$1–6 |
| Public IPv4 addresses ×3 (NAT EIP + 2 ALB IPs) | $0.005 / h each | **$10.95** |
| Route 53 hosted zone | $0.50 / zone + $0.40 / M queries | **$0.50** |
| ACM certificate | free | $0 |
| SSM Session Manager | free | $0 |
| Data transfer out | first 100 GB free, then $0.09 / GB | ~$0 for a dev box |
| **Total** | | **≈ $95–100 / month (~$0.13 / hour)** |

What surprises people: the **NAT gateway and load balancer cost more than the server**. Two ways to cut it:

| Option | Saves | Trade-off |
|---|---|---|
| Run `destroy.sh` when not in use, `create.sh --skip-ns` when needed | everything except $0.50 zone | ~15 min to rebuild; Kafka data is lost |
| Replace the NAT gateway with a tiny NAT *instance* (e.g. `fck-nat` on t4g.nano, ~$3/mo) | ~$30 | one more thing to maintain, single point of failure |
| Bigger instance `t3.large` (8 GB) | costs +$30 | needed if you add Schema Registry / Connect |

## Design notes (why it's built this way)

* **All private except one point.** The EC2 has no public IP and its security group only accepts traffic from the ALB's security group. Admin access is SSM Session Manager through the NAT gateway, so port 22 is never opened.
* **Two hostnames problem solved.** On AWS both the browser and the Kafka UI container reach Keycloak at `https://keycloak.<domain>` (the container goes out via NAT and back in through the ALB), so a single `issuer-uri` with OIDC discovery works and the config is shorter than the local version.
* **Keycloak behind a TLS-terminating proxy** needs `KC_HOSTNAME=https://keycloak.<domain>`, `KC_PROXY_HEADERS=xforwarded` and `KC_HTTP_ENABLED=true`; without them logins loop or redirect to `http://`.
* **Health checks:** ALB probes `/realms/kafka` (Keycloak) and `/actuator/health` (Kafka UI). `create.sh` waits on these so you know the stack is actually usable, not just "instance running".
* **Reboot safe:** the stack is a systemd unit (`kafka-stack.service`); Docker volumes hold Kafka and Keycloak data.
* **Certificate is created before the ALB listener**, using `aws_acm_certificate_validation`, so `terraform apply` won't fail with "certificate not issued".

## Kept simple on purpose — upgrade paths

| Simplification | Production alternative |
|---|---|
| 1 broker, replication factor 1 | 3 brokers across AZs, or Amazon MSK |
| Keycloak `start-dev` with H2 file DB | `start` + RDS PostgreSQL (`KC_DB=postgres`) |
| Passwords in `terraform.tfvars` | AWS Secrets Manager / SSM Parameter Store, read in cloud-init |
| Terraform state on your laptop | S3 backend with state locking |
| Single NAT gateway | one per AZ |
| Single EC2 | Auto Scaling group + EFS/EBS snapshots |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `create.sh` stuck on "Waiting for delegation" | NS change at the registrar can take up to 48 h (usually minutes). Verify with `dig NS yourdomain.com @8.8.8.8` |
| ACM validation times out | Same cause — zone not delegated yet |
| Targets never healthy | `aws ssm start-session`, then `sudo tail -f /var/log/cloud-init-output.log` |
| Keycloak login redirects to `http://` | Check the three `KC_*` proxy variables in `/opt/kafka-stack/docker-compose.yml` |
| Kafka UI restarts in a loop at start | Normal for a minute: it needs Keycloak's discovery document; `restart: unless-stopped` retries |
| `cost.sh` shows no data | Activate the `Project` cost-allocation tag in Billing → Cost allocation tags; wait 24 h |
