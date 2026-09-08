# NiFi launch template example

Builds a hardened EC2 launch template for Apache NiFi using the shared
`launch_template` base module and (optionally) boots one instance from it via
`ec2_instance`.

## What it does

* Renders `templates/user_data.sh.tftpl` into the launch template user data.
  At boot the script installs Corretto + NiFi, mounts a dedicated repository
  volume, applies configuration, and starts NiFi as a systemd service.
* `nifi_properties` – map of `conf/nifi.properties` keys. Existing keys are
  replaced, new ones appended. Merged on top of sensible defaults (HTTPS
  bind, proxy host, repository paths on the data volume).
* `nifi_user_properties` – map written to `conf/custom.properties` and wired
  in through `nifi.variable.registry.properties`, so values are available in
  processors as `${key}`.
* Single-user credentials via `nifi.sh set-single-user-credentials`.
* SSM Session Manager instance profile, IMDSv2, encrypted gp3 volumes.

## Usage

```bash
cd examples/nifi
cp terraform.tfvars.example terraform.tfvars   # edit subnet_id, secrets, maps
terraform init
terraform plan
terraform apply
```

Set `create_instance = false` to produce only the launch template (e.g. for
an Auto Scaling group managed elsewhere).

## Notes

* `nifi_sensitive_props_key` and `nifi_single_user_password` are marked
  sensitive; pass them via `TF_VAR_*` or a secrets-backed tfvars file rather
  than committing them.
* Changing any property map creates a new launch template version. Existing
  instances are not re-configured – replace them to pick up changes.
* Bootstrap log: `/var/log/nifi-bootstrap.log`; NiFi logs under
  `/opt/nifi/logs`.
