# Keycloak (Docker) launch template + internal ALB

Private-only Keycloak deployment using the shared `launch_template` and
`ec2_instance` modules plus an internal Application Load Balancer.

## Topology

```
allowed_cidr_blocks ──► internal ALB (:443/:80, private subnets)
                            │  target group (HTTP :8080, health /health/ready on :9000)
                            ▼
                   EC2 (private subnet, no public IP)
                   └─ docker: quay.io/keycloak/keycloak  start
```

* No public IPs; `associate_public_ip_address` is hard-coded to `false`,
  the ALB is `internal = true`, and `allowed_cidr_blocks` rejects `0.0.0.0/0`.
* Instance SG only accepts traffic from the ALB SG. Admin access via SSM
  Session Manager (no SSH rule at all).
* The instance needs outbound reach for `docker pull` and SSM – give the
  private subnet a NAT gateway or VPC endpoints (ssm, ssmmessages,
  ec2messages, plus registry access).

## Configuration

* `keycloak_env` – any `KC_*` option, merged over defaults that make Keycloak
  work behind the ALB (`KC_PROXY_HEADERS=xforwarded`, `KC_HTTP_ENABLED=true`,
  `KC_HOSTNAME`, health/metrics enabled, DB when `db_url` is set).
* `keycloak_user_properties` – extra entries for `conf/keycloak.conf`
  (mounted read-only into the container).
* `keycloak_extra_args` – appended to `kc.sh start`.
* `keycloak_admin_password`, `db_password` – sensitive; injected only into
  `/etc/keycloak/keycloak.env` (mode 640).

## Usage

```bash
cd examples/keycloak
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan && terraform apply
```

After apply, create a private Route53 alias for `keycloak_hostname` → `alb_dns_name`.

Set `create_instance = false` to build only the template, ALB and target
group, then attach an Auto Scaling group elsewhere. Config changes produce a
new launch template version; replace instances to pick them up.

Logs: `/var/log/keycloak-bootstrap.log`, `journalctl -u keycloak`.
