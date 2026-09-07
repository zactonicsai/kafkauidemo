# Kafka + Keycloak + Kafka UI on AWS — modular Terraform in 3 stages

Same design as before (private VPC, one public ALB "gateway", Route 53 hosted zone, HTTPS), now split so that **Keycloak and Kafka each run on their own EC2** and each layer can be created, updated or destroyed on its own.

```
 Internet ──► Route 53 (example.com) ──► ALB :443 (ACM cert)          [stage 01]
                                          │ host keycloak.* ──► EC2 keycloak :8080   [stage 02]
                                          │ host kafka.*    ──► EC2 kafka+kafka-ui :8090 [stage 03]
              VPC: public subnets (ALB, NAT)  |  private subnets (both EC2, no public IPs, SSM only)
```

## Layout

```
kafka-aws-v2/
├── common.tfvars.example        project / region / domain  -> shared by ALL stages
├── modules/                     reusable building blocks
│   ├── vpc/                     VPC, 2 public + 2 private subnets, IGW, NAT, routes
│   ├── dns/                     hosted zone + DNS-validated ACM certificate
│   ├── alb/                     public ALB, SG, HTTP→HTTPS, HTTPS listener
│   ├── ec2-docker/              private EC2 + SSM role + SG (ALB-only) + Docker install
│   ├── alb-service/             target group + host rule + Route 53 alias (per service)
│   └── network-lookup/          data-only: finds stage-01 resources by tag/name
├── stages/                      each is an independent Terraform root with its own state
│   ├── 01-network/              vpc + dns + alb modules
│   ├── 02-keycloak/             ec2-docker + alb-service + SSM hand-off parameters
│   └── 03-kafka/                ec2-docker + alb-service, reads Keycloak info from SSM
└── scripts/
    ├── create.sh   [network|keycloak|kafka|all]
    ├── destroy.sh  [kafka|keycloak|network|all]     (reverse order, leftover check)
    ├── status.sh                                   per-stage health
    └── cost.sh                                     estimate + real spend per stage
```

## How the stages connect without shared state

* **Stage 02/03 → stage 01:** `modules/network-lookup` finds the VPC (`tag:Name=<project>-vpc`), private subnets (`tag:Tier=private`), the ALB (`<project>-alb`), its 443 listener and the hosted zone by **name/tag** using data sources. No `terraform_remote_state`, so you can run any stage from any machine that has AWS credentials.
* **Stage 03 → stage 02:** Keycloak writes two SSM parameters — `/<project>/keycloak/issuer-url` and `/<project>/keycloak/kafka-ui-client-secret` (SecureString). The Kafka stage reads them and injects them into Kafka UI's config. The secret is typed **once**, in `stages/02-keycloak/terraform.tfvars`.
* **Kafka UI → Keycloak at runtime:** over the public URL `https://keycloak.<domain>` (out through NAT, in through the ALB), so a single `issuer-uri` works.

Every resource is tagged `Project`, `ManagedBy`, and `Stage` (default tags in each provider), which is what `destroy.sh`'s leftover check and `cost.sh`'s per-stage breakdown key on.

## Step-by-step

**Prerequisites:** `aws` (configured), `terraform` ≥ 1.6, `jq`, `dig`, a domain you own.

1. **Configure**
   ```bash
   cp common.tfvars.example common.tfvars                              # domain, region, project
   cp stages/02-keycloak/terraform.tfvars.example stages/02-keycloak/terraform.tfvars   # passwords + client secret
   cp stages/03-kafka/terraform.tfvars.example    stages/03-kafka/terraform.tfvars      # optional: instance size
   # stages/01-network/terraform.tfvars is optional (only vpc_cidr)
   ```
2. **Stage 1 — network**
   ```bash
   ./scripts/create.sh network
   ```
   Creates the hosted zone first, prints the 4 name servers, waits until you set them at your registrar, then builds VPC / NAT / certificate / ALB. (`SKIP_NS=1 ./scripts/create.sh network` skips the wait on later runs.)
3. **Stage 2 — Keycloak**
   ```bash
   ./scripts/create.sh keycloak
   ```
   Waits until `https://keycloak.<domain>` is healthy behind the ALB. Admin console: `admin` / `keycloak_admin_password`.
4. **Stage 3 — Kafka + Kafka UI**
   ```bash
   ./scripts/create.sh kafka
   ```
   Waits until `https://kafka.<domain>` is healthy. Log in with `alice` (admin) or `bob` (read-only).

   Or all three in order: `./scripts/create.sh all`.
5. **Operate**
   ```bash
   ./scripts/status.sh
   ./scripts/cost.sh
   aws ssm start-session --target <instance-id>          # shell on either box; no SSH
   sudo docker compose -f /opt/kafka-stack/docker-compose.yml logs -f kafka-ui
   ```
6. **Destroy** — reverse order, any depth:
   ```bash
   ./scripts/destroy.sh kafka        # only the Kafka box; Keycloak + network stay
   ./scripts/destroy.sh keycloak     # kafka + keycloak; network stays (note: NAT + ALB still bill ~$61/mo)
   ./scripts/destroy.sh all          # everything; remove NS records at the registrar afterwards
   ```

### Running Terraform by hand

Each stage is a normal root module:

```bash
cd stages/02-keycloak
terraform init
terraform plan  -var-file=../../common.tfvars -var-file=terraform.tfvars
terraform apply -var-file=../../common.tfvars -var-file=terraform.tfvars
```

## Cost (us-east-1, on-demand, 24 × 7, approximate)

| Stage | Resource | Rate | Per month |
|---|---|---|---|
| 01-network | NAT Gateway | $0.045 / h + $0.045 / GB | $32.85 |
| 01-network | Application Load Balancer | $0.0225 / h + LCU | $16.40 + $1–6 |
| 01-network | Public IPv4 × 3 (NAT + 2 ALB) | $0.005 / h each | $10.95 |
| 01-network | Route 53 hosted zone | $0.50 + $0.40 / M queries | $0.50 |
| 01-network | ACM cert, VPC, IGW, subnets | free | $0 |
| | **Stage 01 subtotal** | | **≈ $61** |
| 02-keycloak | EC2 `t3.small` (2 vCPU, 2 GB) | $0.0208 / h | $15.20 |
| 02-keycloak | EBS gp3 20 GB | $0.08 / GB | $1.60 |
| 02-keycloak | SSM Parameter Store (standard) | free | $0 |
| | **Stage 02 subtotal** | | **≈ $17** |
| 03-kafka | EC2 `t3.medium` (2 vCPU, 4 GB) | $0.0416 / h | $30.40 |
| 03-kafka | EBS gp3 30 GB | $0.08 / GB | $2.40 |
| | **Stage 03 subtotal** | | **≈ $33** |
| all | SSM Session Manager, data out < 100 GB | free | $0 |
| | **Total** | | **≈ $111–116 / month (~$0.16 / h)** |

Compared with the single-instance version (~$95–100) you pay ~$17 more for the second box and get isolation: you can rebuild Kafka without touching Keycloak's users, or resize either one independently. Note that the "empty" network stage still costs ~$61/month because of the NAT Gateway and ALB — destroy it too if the environment will sit idle for weeks (rebuilding takes ~10 min; the only thing you lose is the zone's name-server set, and the two-phase create handles that).

## Reuse ideas

* **Another service behind the same gateway** (Schema Registry, Grafana…): new stage with `ec2-docker` + `alb-service`, pick a free `priority` and hostname, and add the hostname to `certificate_hosts` in stage 01.
* **Another environment** (`dev` / `prod`): a second `common.tfvars` with a different `project` and domain; every resource name and tag is derived from `project`, so they don't collide in one account.
* **Team state:** replace `backend "local" {}` in each stage's `providers.tf` with an S3 backend using a different `key` per stage (`network.tfstate`, `keycloak.tfstate`, `kafka.tfstate`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| Stage 02/03 fails with "no matching VPC / LB found" | Stage 01 isn't applied, or `project` differs between `common.tfvars` runs |
| Stage 03 fails on `data.aws_ssm_parameter` | Stage 02 isn't applied yet (it writes the parameters) |
| Kafka UI target never healthy | Keycloak must be healthy first (UI fetches the OIDC discovery document at start). Check `sudo tail -f /var/log/cloud-init-output.log` via SSM |
| Keycloak login redirects to `http://` | `KC_HOSTNAME` / `KC_PROXY_HEADERS` in `/opt/keycloak-stack/docker-compose.yml` |
| ACM validation hangs | Domain not delegated yet: `dig NS <domain> @8.8.8.8` |
| Changed a password in stage 02 tfvars | `user_data_replace_on_change` recreates the Keycloak instance (H2 data is lost — export the realm first if you added users by hand) |
