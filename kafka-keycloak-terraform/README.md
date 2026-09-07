# Kafka + Keycloak on AWS — modular Terraform

The original single `main.tf` is split into reusable **base modules** and two
**stacks** that run as separate processes:

```
.
├── modules/                     # reusable building blocks (no hard-coded values)
│   ├── vpc/                     # VPC, IGW, public/private subnets, route tables, optional NAT
│   ├── security_groups/         # map-driven SGs; rules can reference other SGs by key
│   ├── iam_instance_role/       # EC2 role + managed/inline policies + instance profile
│   ├── elastic_ip/              # stable public IPv4
│   ├── launch_template/         # hardened base launch template (IMDSv2, encrypted gp3, user-data)
│   └── ec2_instance/            # instance from a launch template + optional EIP association
│
├── stacks/
│   ├── 10-network/              # PROCESS 1: VPC, subnets, security groups, IAM roles
│   │   ├── main.tf variables.tf outputs.tf providers.tf versions.tf
│   │   └── dev.tfvars
│   └── 20-apps/                 # PROCESS 2: Keycloak + Kafka/Kafka UI EC2
│       ├── main.tf locals.tf data.tf variables.tf outputs.tf providers.tf versions.tf
│       ├── files/  templates/   # unchanged compose / realm / user-data templates
│       └── dev.tfvars
├── Makefile
└── README.md
```

## Deploy (two processes, in order)

```bash
# 1. Network: VPC, subnets, SGs, IAM
terraform -chdir=stacks/10-network init
terraform -chdir=stacks/10-network apply -var-file=dev.tfvars

# 2. Apps: Keycloak, Kafka + Kafka UI
terraform -chdir=stacks/20-apps init
terraform -chdir=stacks/20-apps apply -var-file=dev.tfvars
```

Or `make all ENV=dev`. Destroy in reverse (`make destroy ENV=dev`).

The apps stack discovers the network via `terraform_remote_state`
(`network_state` in `dev.tfvars`, local file by default). Point both stacks at
S3 for shared use — the commented `backend "s3"` blocks in each `versions.tf`
and the `network_state` example show the matching settings.

## What tfvars control

### `stacks/10-network/dev.tfvars`

| Setting | Purpose |
|---|---|
| `availability_zone` / `instance_types_for_az_selection` | Pin an AZ, or auto-pick the first AZ that offers every listed instance type (preserves the original behaviour). |
| `vpc_cidr`, `public_subnets`, `private_subnets`, `create_nat_gateway` | Any number of subnets, keyed by name; per-subnet AZ optional. |
| `allowed_cidr` + `security_groups` | Fully data-driven SG rules. Write `cidr_ipv4 = "ALLOWED_CIDR"` to reuse `allowed_cidr`; use `source_security_group_key = "kafka"` for SG-to-SG rules. |
| `instance_roles` | Any number of roles/instance profiles with managed or inline policies. |

Outputs are maps keyed by the same names (`public_subnet_ids["public-a"]`,
`security_group_ids["keycloak"]`, `instance_profile_names["ec2_ssm"]`).

### `stacks/20-apps/dev.tfvars`

| Setting | Purpose |
|---|---|
| `network_state` | Where to read the network stack outputs (local or s3). |
| `network.*_key` | Which subnet / SGs / instance profile to use, by key. |
| `network.subnet_id`, `*_security_group_ids`, `instance_profile_name` | Optional direct IDs — bypass remote state and deploy into any existing VPC. |
| `ami_id` / `ami_ssm_parameter` | Explicit AMI, or resolve latest AL2023 via SSM. |
| `keycloak = { ... }` | `enabled`, `instance_type`, `root_volume_size/type`, `key_name`, `admin_username`, optional `admin_password`, `tags`. |
| `kafka = { ... }` | `enabled`, `instance_type`, `root_volume_size/type`, `key_name`, `ui_username`, optional `ui_password`, `tags`. |

Passwords not supplied in tfvars are generated with `random_password`, as before,
and exposed as sensitive outputs.

## Reusing the base modules

Each module is self-contained and value-free. Example — a third service:

```hcl
module "grafana_lt" {
  source                    = "../../modules/launch_template"
  name                      = "${var.project_name}-grafana"
  image_id                  = local.ami_id
  instance_type             = "t3.small"
  iam_instance_profile_name = local.instance_profile_name
  subnet_id                 = local.subnet_id
  security_group_ids        = [local.net.security_group_ids["grafana"]]
  user_data                 = file("${path.module}/templates/grafana.sh")
}

module "grafana" {
  source                  = "../../modules/ec2_instance"
  name                    = "${var.project_name}-grafana"
  launch_template_id      = module.grafana_lt.id
  launch_template_version = tostring(module.grafana_lt.latest_version)
}
```

Add the `grafana` security group to the network stack's `security_groups` map
and it flows through automatically.

## Multiple environments

Copy `dev.tfvars` to `prod.tfvars` in each stack, change values (CIDRs, sizes,
`allowed_cidr`, `project_name`), and run with `-var-file=prod.tfvars`
(`make all ENV=prod`). Use separate backend keys or workspaces per environment.

## Migrating from the original single-state project

Resource addresses have changed and the state is now split in two, so the
existing `terraform.tfstate` will not apply cleanly. Two options:

1. **Lab / disposable (recommended):** `terraform destroy` with the old code,
   then deploy the new stacks.
2. **Keep resources:** move state with `terraform state mv -state=old.tfstate -state-out=...`
   into each stack. Key mappings:

   | Old address | New address |
   |---|---|
   | `aws_vpc.main` | `10-network: module.vpc.aws_vpc.this` |
   | `aws_subnet.public` | `10-network: module.vpc.aws_subnet.public["public-a"]` |
   | `aws_security_group.kafka` | `10-network: module.security_groups.aws_security_group.this["kafka"]` |
   | `aws_iam_role.ec2_ssm` | `10-network: module.instance_roles["ec2_ssm"].aws_iam_role.this` |
   | `aws_eip.kafka` | `20-apps: module.kafka_eip[0].aws_eip.this` |
   | `aws_launch_template.kafka` | `20-apps: module.kafka_launch_template[0].aws_launch_template.this` |
   | `aws_instance.kafka` | `20-apps: module.kafka[0].aws_instance.this` |

   Inline SG `ingress`/`egress` blocks became `aws_vpc_security_group_*_rule`
   resources and the route became `aws_route.public_internet`; those will be
   recreated (non-disruptive).

## Notes

- `terraform fmt` passes across the tree. Run `make validate` once providers are
  reachable in your environment.
- All behaviour of the original (AZ selection, IMDSv2, encrypted volumes, EIP
  allocation before user-data rendering, Kafka waiting on Keycloak) is preserved.
