# Kafka + Keycloak + Kafka UI on AWS — pure AWS CLI (no Terraform)

Builds and destroys **the same resources as `kafka-aws-v2`** (VPC, public/private subnets, IGW, NAT, ALB gateway, hosted zone, ACM cert, private Keycloak EC2, private Kafka + Kafka UI EC2, SSM hand-off) using only `aws` CLI commands in bash, in the same three independent stages.

Resource IDs are written to `state/<stage>.env` as they're created so `destroy` can remove them in reverse order. Cross-stage references (VPC, subnets, ALB, listener, hosted zone) are looked up **by tag/name**, exactly like the Terraform `network-lookup` module, so stages don't need each other's state files.

```
kafka-aws-cli/
├── config.env.example     project / region / domain / passwords / sizes  (copy to config.env)
├── create.sh              [network|keycloak|kafka|all]
├── destroy.sh             [kafka|keycloak|network|all] [--yes]   reverse order + leftover check
├── status.sh              per-stage instance + target health
├── cost.sh                fixed estimate + real spend per Stage tag
├── lib/
│   ├── common.sh          state store, tag helpers, network lookup, reusable "docker host" + "publish service" functions
│   └── install_docker.sh  cloud-init prefix (Docker + Compose)
├── stages/
│   ├── 01-network/        create.sh / destroy.sh
│   ├── 02-keycloak/       create.sh / destroy.sh / user_data.sh.tpl
│   └── 03-kafka/          create.sh / destroy.sh / user_data.sh.tpl
└── state/                 generated: 01-network.env, 02-keycloak.env, 03-kafka.env  (git-ignored)
```

## Prerequisites

`aws` CLI v2 (configured), `jq`, `dig`, `envsubst` (package `gettext`), a domain you own.

## Step-by-step

```bash
cp config.env.example config.env && nano config.env      # domain, passwords, client secret

./create.sh network      # VPC, NAT, hosted zone → prints NS → waits for delegation → cert → ALB   (~10 min + DNS)
./create.sh keycloak     # IAM role, SG, EC2, target group, host rule, DNS record, SSM params    (~5 min)
./create.sh kafka        # same for Kafka + Kafka UI, reading Keycloak details from SSM         (~5 min)
# or: ./create.sh all

./status.sh
./cost.sh

./destroy.sh kafka       # only Kafka
./destroy.sh keycloak    # Kafka, then Keycloak
./destroy.sh all         # everything, then verifies nothing billable is left
```

Re-running a stage that already has state is refused (destroy it first). If the NS-delegation wait was interrupted, the hosted zone already exists; delete `state/01-network.env`, delete the zone in the console, and re-run — or simply let the wait finish, it's the only step that needs you.

## What each stage runs (AWS CLI calls)

**01-network** — `ec2 create-vpc`, `modify-vpc-attribute` ×2, `create-internet-gateway` + `attach`, `create-subnet` ×4, `allocate-address`, `create-nat-gateway` + `wait nat-gateway-available`, `create-route-table` ×2, `create-route` ×2, `associate-route-table` ×4, `create-security-group` + `authorize-security-group-ingress`, `route53 create-hosted-zone`, `acm request-certificate`, `route53 change-resource-record-sets` (validation CNAMEs), `acm wait certificate-validated`, `elbv2 create-load-balancer` + `wait`, `create-listener` ×2 (80 redirect, 443 fixed-404 with cert).

**02-keycloak** — lookup network; `iam create-role`, `attach-role-policy` (SSM), `create-instance-profile`, `add-role-to-instance-profile`; `ec2 create-security-group` (8080 from ALB SG only); `ssm get-parameter` (latest AL2023 AMI); `ec2 run-instances` (private subnet, no public IP, gp3 encrypted, IMDSv2, user-data); `elbv2 create-target-group`, `register-targets`, `create-rule` (host `keycloak.<domain>`, priority 10); `route53 change-resource-record-sets` (alias A); `ssm put-parameter` ×2; wait for target healthy.

**03-kafka** — same pattern with port 8090, host `kafka.<domain>`, priority 20, and `ssm get-parameter --with-decryption` for the client secret.

Destroy scripts run each list backwards, waiting on NAT gateway and load balancer deletion and clearing the hosted zone's records before deleting the zone.

## Cost

Identical resources → identical cost to `kafka-aws-v2`: **≈ $111–116 / month** (network ~$61 with NAT + ALB + IPv4s, Keycloak `t3.small` ~$17, Kafka `t3.medium` ~$33). `./cost.sh` prints the table and the real month-to-date spend grouped by the `Stage` tag (activate the `Project` and `Stage` cost-allocation tags once in Billing).

## Terraform vs CLI — when to use which

| | Terraform (`kafka-aws-v2`) | AWS CLI (`kafka-aws-cli`) |
|---|---|---|
| Change a setting later | `apply` computes the diff | destroy + create the stage |
| Drift detection | `plan` shows it | none |
| Knows what it created | state file, locked in S3 for teams | `state/*.env` on one machine |
| Dependencies | in the CLI script order you see | explicit — good for learning what actually gets called |
| Extra tooling | Terraform binary | none beyond `aws`, `jq`, `dig`, `envsubst` |
| Partial failure | re-run `apply` continues | re-run refused; run `destroy` for that stage, then `create` |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `VPC kafka-stack-vpc not found` | Stage 01 not created or `PROJECT` differs from the one used to create it |
| `SSM parameter missing` | Stage 02 not created |
| `InvalidParameterValue ... instance profile` on `run-instances` | IAM propagation — the script sleeps 10 s; if it still fails, wait and destroy/re-create the stage |
| `DependencyViolation` deleting the VPC | Something (ENI, SG) still attached: `aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=<id>`; delete it and re-run `destroy` |
| Cert validation hangs | `dig NS <domain> @8.8.8.8` must return the zone's name servers |
| Target never healthy | `aws ssm start-session --target <id>`, then `sudo tail -f /var/log/cloud-init-output.log` |
