# Kafka + Kafka UI + Keycloak on Two EC2 Instances

This project creates a small AWS lab where **Keycloak runs on its own EC2 instance** and **Kafka + Kafka UI run on a second EC2 instance**.

The split is intentional. Kafka and Keycloak are both Java applications and can compete for memory when they share one small EC2 instance. Giving Keycloak its own EC2 makes Docker restarts and memory troubleshooting much easier.

---

## 1. Architecture

```text
                         Your browser
                             |
              +--------------+--------------+
              |                             |
              | TCP 8080                    | TCP 8081
              v                             v
     +--------------------+        +--------------------+
     | Kafka EC2          |        | Keycloak EC2       |
     |                    |        |                    |
     | Elastic IP #1      |        | Elastic IP #2      |
     |                    |        |                    |
     | Docker             |        | Docker             |
     |  + Kafka           |        |  + Keycloak        |
     |  + Kafka UI        |        |                    |
     +---------+----------+        +----------+---------+
               |                              ^
               | OIDC token/JWK/userinfo      |
               | private VPC TCP 8081         |
               +------------------------------+
```

### Public traffic

- Kafka UI: `http://KAFKA_EIP:8080`
- Keycloak: `http://KEYCLOAK_EIP:8081`
- Kafka port `9092` is **not opened to the Internet**.
- SSH port `22` is **not opened**.
- EC2 administration is done through AWS Systems Manager Session Manager.

### Private traffic

Kafka UI talks to Keycloak using Keycloak's **private VPC IP address** for the OIDC token, JWK, and user-info endpoints.

That means this server-to-server traffic stays inside the VPC.

---

# 2. Why Keycloak is on a separate EC2

Originally Kafka, Kafka UI, and Keycloak shared one EC2 instance.

That is easy to build, but it has an important downside:

```text
One EC2
 |
 +-- Kafka JVM
 +-- Kafka UI JVM
 +-- Keycloak JVM
```

All three Java processes compete for the same RAM.

If memory becomes tight, Linux may kill one of the containers. Docker sees the container stop and starts it again because the Compose file uses:

```yaml
restart: unless-stopped
```

That looks like containers are "cycling" or continuously restarting.

The new design is:

```text
Kafka EC2
 +-- Kafka
 +-- Kafka UI

Keycloak EC2
 +-- Keycloak
```

This is still a lab design, but it separates the major workloads and makes troubleshooting much simpler.

---

# 3. Files

```text
kafka-keycloak-ec2/
├── main.tf
├── terraform.tfvars.example
├── README.md
│
├── files/
│   ├── docker-compose.yml.tftpl
│   ├── keycloak-compose.yml.tftpl
│   ├── kafka-ui.yml.tftpl
│   └── keycloak-realm.json.tftpl
│
└── templates/
    ├── user_data.sh.tftpl
    └── keycloak_user_data.sh.tftpl
```

## `main.tf`

Creates the AWS infrastructure:

- VPC
- public subnet
- Internet Gateway
- public route table
- Kafka security group
- Keycloak security group
- IAM role for SSM
- instance profile
- Kafka Elastic IP
- Keycloak Elastic IP
- Kafka Launch Template
- Keycloak Launch Template
- Kafka EC2
- Keycloak EC2

## `templates/user_data.sh.tftpl`

Runs only on the **Kafka EC2**.

It:

1. installs Docker
2. enables Docker at boot
3. verifies Docker is running
4. installs Docker Compose
5. writes the Kafka Compose file
6. writes the Kafka UI OIDC configuration
7. pulls Kafka and Kafka UI images
8. starts the Compose stack
9. creates a systemd service so it starts again after reboot

## `templates/keycloak_user_data.sh.tftpl`

Runs only on the **Keycloak EC2**.

It:

1. installs Docker
2. enables Docker at boot
3. verifies Docker is running
4. installs Docker Compose
5. writes the Keycloak Compose file
6. writes the Keycloak realm import file
7. validates the JSON
8. pulls the Keycloak image
9. starts Keycloak
10. creates a systemd service so Keycloak starts after reboot
11. waits for the OIDC discovery endpoint

---

# 4. Amazon Linux curl fix

Do **not** change the user-data scripts back to:

```bash
dnf install -y docker curl
```

Amazon Linux 2023 normally has `curl-minimal` installed already.

Trying to install full `curl` can produce errors such as:

```text
package curl-minimal conflicts with curl
```

This project instead does:

```bash
dnf install -y docker

if ! command -v curl >/dev/null 2>&1; then
  dnf install -y curl-minimal
fi
```

That is enough for the HTTPS downloads used by the bootstrap.

---

# 5. Instance sizes

Defaults:

```hcl
kafka_instance_type    = "t3.medium"
keycloak_instance_type = "t3.small"
```

For a lab this is much more predictable than putting every Java service on one `t3.medium`.

The Kafka host runs:

```text
Kafka
Kafka UI
```

The Keycloak host runs only:

```text
Keycloak
```

If you still see OOM kills, increase the appropriate instance type instead of increasing all services at once.

---

# 6. Configure Terraform variables

Copy:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Example:

```hcl
aws_region   = "us-east-1"
project_name = "kafka-keycloak-lab"

kafka_instance_type    = "t3.medium"
keycloak_instance_type = "t3.small"

allowed_cidr = "YOUR_PUBLIC_IP/32"

kafka_ui_username       = "kafkauser"
keycloak_admin_username = "admin"
```

## Find your public IP

For a temporary lab, find the public IPv4 address of the computer/browser that will access the services and use:

```text
YOUR_IP/32
```

For example:

```hcl
allowed_cidr = "198.51.100.25/32"
```

Do not literally use that example address.

You can use:

```hcl
allowed_cidr = "0.0.0.0/0"
```

for troubleshooting, but that exposes Kafka UI and Keycloak to the entire Internet and is not recommended.

---

# 7. Create the lab

Run:

```bash
terraform init
```

Then:

```bash
terraform validate
```

Then:

```bash
terraform plan
```

Review the plan carefully.

Finally:

```bash
terraform apply
```

Enter:

```text
yes
```

---

# 8. Important migration note

The previous version used one resource named:

```text
aws_instance.stack
```

The new design uses:

```text
aws_instance.kafka
aws_instance.keycloak
```

Therefore Terraform will normally destroy the old single EC2 and create the two new EC2 instances.

That is expected.

This is a lab project, so the simplest migration is to let Terraform replace the old instance.

Always inspect:

```bash
terraform plan
```

before applying.

---

# 9. Terraform outputs

Run:

```bash
terraform output
```

Important outputs include:

```text
kafka_instance_id
keycloak_instance_id
kafka_public_ip
keycloak_public_ip
keycloak_private_ip
kafka_ui_url
keycloak_url
keycloak_admin_url
ssm_kafka
ssm_keycloak
```

Get Kafka UI URL:

```bash
terraform output -raw kafka_ui_url
```

Get Keycloak URL:

```bash
terraform output -raw keycloak_url
```

---

# 10. Get the generated passwords

Kafka UI demo user's password:

```bash
terraform output -raw kafka_ui_user_password
```

The username defaults to:

```text
kafkauser
```

Keycloak administrator password:

```bash
terraform output -raw keycloak_admin_password
```

Administrator username:

```bash
terraform output -raw keycloak_admin_username
```

Remember: these passwords are stored in Terraform state. That is acceptable for this simple lab, but production systems should use a proper secrets-management approach.

---

# 11. Keycloak realm configuration

At first startup Keycloak imports:

```text
/opt/keycloak-stack/keycloak-realm.json
```

The realm is:

```text
kafka-ui
```

Terraform automatically creates:

```text
Realm:     kafka-ui
Client:    kafka-ui
User:      kafkauser
Protocol:  OpenID Connect
```

The Kafka UI client is confidential and has a generated client secret.

---

# 12. How Kafka UI OIDC works

This part is important because there are **two different network paths**.

## Browser/front-channel

Your browser needs to see Keycloak.

Kafka UI sends the browser to:

```text
http://KEYCLOAK_PUBLIC_IP:8081/realms/kafka-ui/protocol/openid-connect/auth
```

The user logs in.

Keycloak redirects the browser back to:

```text
http://KAFKA_PUBLIC_IP:8080/login/oauth2/code/keycloak
```

That callback URL is also registered in the Keycloak client.

## Server/back-channel

After receiving the authorization code, Kafka UI must exchange it for tokens.

Kafka UI does that directly against Keycloak's private VPC IP:

```text
http://KEYCLOAK_PRIVATE_IP:8081/realms/kafka-ui/protocol/openid-connect/token
```

It also uses the private address for:

```text
/certs
/userinfo
```

This traffic does not need to leave the VPC.

---

# 13. Security groups

There are now two security groups.

## Kafka security group

Inbound:

```text
TCP 8080 from allowed_cidr
```

There is deliberately no public inbound rule for:

```text
9092 Kafka
22   SSH
```

## Keycloak security group

Inbound:

```text
TCP 8081 from allowed_cidr
```

and:

```text
TCP 8081 from the Kafka EC2 security group
```

That second rule is what allows Kafka UI to call Keycloak privately.

---

# 14. Connect to Kafka EC2 with SSM

Get the command:

```bash
terraform output -raw ssm_kafka
```

Or run:

```bash
aws ssm start-session \
  --region us-east-1 \
  --target $(terraform output -raw kafka_instance_id)
```

No SSH key or port 22 is required.

---

# 15. Connect to Keycloak EC2 with SSM

```bash
aws ssm start-session \
  --region us-east-1 \
  --target $(terraform output -raw keycloak_instance_id)
```

---

# 16. Verify the Keycloak EC2 first

Keycloak should be healthy before debugging Kafka UI authentication.

Connect to the Keycloak EC2 and run:

```bash
sudo systemctl status docker --no-pager
```

Then:

```bash
sudo docker ps
```

Expected container:

```text
keycloak
```

Check Compose:

```bash
cd /opt/keycloak-stack
sudo docker compose ps
```

Check local HTTP connectivity:

```bash
curl -i http://127.0.0.1:8081/
```

Check the realm discovery URL:

```bash
curl -s \
  http://127.0.0.1:8081/realms/kafka-ui/.well-known/openid-configuration
```

If this works, Docker and Keycloak are working locally.

---

# 17. Check Keycloak container logs

```bash
cd /opt/keycloak-stack
sudo docker compose logs --tail=200 keycloak
```

Follow logs live:

```bash
sudo docker compose logs -f keycloak
```

Check whether the container is restarting:

```bash
sudo docker inspect keycloak \
  --format 'status={{.State.Status}} restart={{.RestartCount}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} error={{.State.Error}}'
```

A healthy result should look approximately like:

```text
status=running restart=0 exit=0 oom=false
```

---

# 18. Verify Kafka EC2

Connect to the Kafka EC2.

Check Docker:

```bash
sudo systemctl status docker --no-pager
```

Check containers:

```bash
sudo docker ps
```

Expected:

```text
kafka
kafka-ui
```

Then:

```bash
cd /opt/kafka-stack
sudo docker compose ps
```

---

# 19. Test Kafka UI locally on the EC2

Run:

```bash
curl -I http://127.0.0.1:8080
```

A redirect response is normal because authentication is enabled.

You may see something similar to:

```text
HTTP/1.1 302 Found
```

A `302` is not a failure here. It usually means Kafka UI is redirecting the browser into the login process.

---

# 20. Test Kafka EC2 -> Keycloak EC2 private networking

Get Keycloak's private IP from your local machine:

```bash
terraform output -raw keycloak_private_ip
```

Suppose it returns:

```text
10.40.1.25
```

On the Kafka EC2 run:

```bash
curl -i http://10.40.1.25:8081/
```

Then test OIDC discovery:

```bash
curl -s \
  http://10.40.1.25:8081/realms/kafka-ui/.well-known/openid-configuration
```

If the local Keycloak test works on Keycloak EC2 but this private-IP test fails from Kafka EC2, focus on:

```text
VPC routing
Keycloak security group
container port publishing
Keycloak host firewall
```

In this project both EC2 instances are in the same VPC/subnet, so the VPC automatically has a `local` route between them.

---

# 21. Check listening ports on Keycloak EC2

Run:

```bash
sudo ss -lntp
```

You should see a listener associated with Docker on port:

```text
8081
```

Also run:

```bash
sudo docker port keycloak
```

Expected approximately:

```text
8080/tcp -> 0.0.0.0:8081
```

The important part is:

```text
0.0.0.0:8081
```

That means the container's port is published on the EC2 network interfaces, not only on localhost.

---

# 22. Check listening ports on Kafka EC2

```bash
sudo ss -lntp
```

You should see host port:

```text
8080
```

Check Docker mapping:

```bash
sudo docker port kafka-ui
```

Expected approximately:

```text
8080/tcp -> 0.0.0.0:8080
```

---

# 23. Why `curl localhost` can work while browser access fails

This is a very useful troubleshooting distinction.

If this works on the EC2:

```bash
curl http://127.0.0.1:8081
```

but this fails from your laptop:

```text
http://KEYCLOAK_PUBLIC_IP:8081
```

then the application itself is probably okay.

Look at:

```text
Security Group inbound rule
allowed_cidr
Elastic IP association
route table
Internet Gateway
Docker host port binding
```

Do not immediately change the Keycloak container configuration when the local EC2 curl already works.

---

# 24. Why public curl can fail from the same EC2

Do not use a service's own Elastic IP as your primary local health check.

For example, on Keycloak EC2 prefer:

```bash
curl http://127.0.0.1:8081
```

instead of:

```bash
curl http://KEYCLOAK_EIP:8081
```

The localhost check answers a simpler question:

> Is the container/service listening correctly on this EC2?

Then test private VPC connectivity from the other EC2.

Finally test public connectivity from your browser/laptop.

Troubleshoot one layer at a time.

---

# 25. Container restart/cycling troubleshooting

List all containers including stopped containers:

```bash
sudo docker ps -a
```

Check restart count:

```bash
sudo docker inspect kafka \
  --format 'restart={{.RestartCount}} status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}'
```

```bash
sudo docker inspect kafka-ui \
  --format 'restart={{.RestartCount}} status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}'
```

On Keycloak EC2:

```bash
sudo docker inspect keycloak \
  --format 'restart={{.RestartCount}} status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}'
```

If you see:

```text
oom=true
```

Linux killed the process because the host ran short of memory.

Check memory:

```bash
free -h
```

and:

```bash
sudo dmesg | grep -i -E 'oom|killed process|out of memory'
```

---

# 26. Bootstrap logs

Kafka host:

```bash
sudo tail -200 /var/log/kafka-bootstrap.log
```

Keycloak host:

```bash
sudo tail -200 /var/log/keycloak-bootstrap.log
```

Cloud-init output is also useful:

```bash
sudo tail -200 /var/log/cloud-init-output.log
```

Check whether cloud-init completed:

```bash
cloud-init status --long
```

---

# 27. Docker service troubleshooting

Check Docker:

```bash
sudo systemctl status docker --no-pager
```

If it is stopped:

```bash
sudo systemctl restart docker
```

Check logs:

```bash
sudo journalctl -u docker -n 200 --no-pager
```

Verify Docker can respond:

```bash
sudo docker info
```

---

# 28. Compose systemd services

Kafka EC2 has:

```text
kafka-compose.service
```

Check it:

```bash
sudo systemctl status kafka-compose.service --no-pager
```

Restart it:

```bash
sudo systemctl restart kafka-compose.service
```

Keycloak EC2 has:

```text
keycloak-compose.service
```

Check it:

```bash
sudo systemctl status keycloak-compose.service --no-pager
```

Restart:

```bash
sudo systemctl restart keycloak-compose.service
```

---

# 29. OIDC redirect URI gotcha

OIDC redirect URIs must match exactly.

The Keycloak client contains a redirect similar to:

```text
http://KAFKA_EIP:8080/login/oauth2/code/keycloak
```

These are all different URLs to Keycloak:

```text
http://1.2.3.4:8080/login/oauth2/code/keycloak
http://1.2.3.4/login/oauth2/code/keycloak
https://1.2.3.4:8080/login/oauth2/code/keycloak
http://1.2.3.5:8080/login/oauth2/code/keycloak
```

A changed IP, port, protocol, or callback path can cause an invalid redirect URI error.

This project uses Elastic IPs to keep those URLs stable.

---

# 30. OIDC issuer / public-hostname gotcha

Keycloak identifies itself using the configured public hostname:

```text
http://KEYCLOAK_EIP:8081
```

The browser should always use that public address.

Kafka UI's backend is allowed to contact Keycloak through its private VPC IP for direct server-to-server API calls.

If you later change from HTTP to HTTPS or put Keycloak behind a load balancer, update **all** of the following together:

```text
Keycloak KC_HOSTNAME
Kafka UI authorization URI
Kafka UI token URI if appropriate
JWK URI
userinfo URI
Keycloak redirect URIs
Keycloak web origins
```

OIDC is sensitive to URL mismatches.

---

# 31. Kafka UI logs

On Kafka EC2:

```bash
cd /opt/kafka-stack
sudo docker compose logs --tail=200 kafka-ui
```

Look for terms such as:

```text
oauth
oidc
keycloak
connection refused
timeout
redirect
client secret
401
403
```

Follow live:

```bash
sudo docker compose logs -f kafka-ui
```

---

# 32. Kafka logs

```bash
cd /opt/kafka-stack
sudo docker compose logs --tail=200 kafka
```

Useful checks:

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --list
```

Create a test topic:

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --create \
  --topic test-topic \
  --partitions 1 \
  --replication-factor 1
```

List again:

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --list
```

---

# 33. Test the login flow

First verify Keycloak directly in a browser:

```text
http://KEYCLOAK_EIP:8081
```

Then open Kafka UI:

```text
http://KAFKA_EIP:8080
```

Kafka UI should redirect you to Keycloak.

Login using:

```text
username: kafkauser
password: terraform output -raw kafka_ui_user_password
```

After successful authentication, Keycloak redirects you back to Kafka UI.

---

# 34. If Kafka UI says connection refused to Keycloak

First get Keycloak private IP:

```bash
terraform output -raw keycloak_private_ip
```

From Kafka EC2:

```bash
curl -v http://KEYCLOAK_PRIVATE_IP:8081/
```

If that fails, check Keycloak's SG:

```bash
aws ec2 describe-security-groups \
  --region us-east-1 \
  --group-ids YOUR_KEYCLOAK_SECURITY_GROUP_ID
```

There should be an inbound rule allowing TCP `8081` from the **Kafka security group**.

Also verify on Keycloak EC2:

```bash
sudo ss -lntp | grep 8081
```

---

# 35. If Kafka UI opens but login loops

Common causes:

1. wrong redirect URI
2. stale browser cookies
3. changed Elastic IP
4. incorrect OIDC client secret
5. Keycloak realm was imported before the expected configuration changed

For a disposable lab, the easiest way to force a clean Keycloak realm import is to recreate the Keycloak EC2 and its Docker volume.

You can replace just Keycloak EC2 with:

```bash
terraform apply -replace=aws_instance.keycloak
```

Because the Docker volume lives on the instance's root disk, replacing the instance gives Keycloak a fresh local data directory.

---

# 36. If changing user-data does not affect an existing EC2

EC2 user-data normally runs during the instance's first boot.

Updating the Launch Template creates a new version, but the already-running instance does not magically rerun the bootstrap.

For this lab, replace the appropriate instance.

Kafka host:

```bash
terraform apply -replace=aws_instance.kafka
```

Keycloak host:

```bash
terraform apply -replace=aws_instance.keycloak
```

Both:

```bash
terraform apply \
  -replace=aws_instance.kafka \
  -replace=aws_instance.keycloak
```

Always inspect the plan first when the instances contain data you care about.

---

# 37. Public network troubleshooting checklist

If a browser cannot reach Kafka UI or Keycloak, check in this order.

## A. Is the container running?

```bash
sudo docker ps
```

## B. Can EC2 reach it locally?

Kafka:

```bash
curl -I http://127.0.0.1:8080
```

Keycloak:

```bash
curl -I http://127.0.0.1:8081
```

## C. Is Docker publishing the port?

```bash
sudo ss -lntp
```

## D. Is the Elastic IP attached to the correct EC2?

```bash
aws ec2 describe-addresses --region us-east-1
```

## E. Does the security group allow your current public IP?

Your home/office/VPN IP may change.

## F. Does the subnet route to the Internet Gateway?

The route table should contain:

```text
0.0.0.0/0 -> igw-xxxxxxxx
```

---

# 38. Check AWS instances

```bash
aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=tag:Name,Values=*kafka-keycloak-lab*" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,Id:InstanceId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,State:State.Name}' \
  --output table
```

You should see two instances:

```text
kafka-keycloak-lab-kafka-ec2
kafka-keycloak-lab-keycloak-ec2
```

---

# 39. SSM troubleshooting

If Session Manager says the instance is not connected, check the EC2 IAM instance profile and confirm the role has:

```text
AmazonSSMManagedInstanceCore
```

On the instance:

```bash
sudo systemctl status amazon-ssm-agent --no-pager
```

Restart if needed:

```bash
sudo systemctl restart amazon-ssm-agent
```

---

# 40. Cost notes

This design costs more than the single-host design because there are now two running EC2 instances and two Elastic IPv4 addresses.

The tradeoff is isolation and simpler troubleshooting.

For temporary labs, destroy resources when finished:

```bash
terraform destroy
```

Review the plan and enter:

```text
yes
```

---

# 41. Production warnings

This project is intentionally simple and designed for learning/testing.

It is **not a production Keycloak/Kafka architecture**.

Production systems should normally consider:

- HTTPS/TLS
- private subnets
- an Application Load Balancer or other ingress layer
- DNS names instead of raw IP addresses
- external PostgreSQL for Keycloak
- multi-node Kafka
- Kafka authentication and TLS
- proper secret storage
- restricted security groups
- backups
- monitoring
- log collection
- multi-AZ design
- patching strategy
- autoscaling where appropriate

Keycloak here uses:

```text
start-dev
```

which is intentionally a development-mode setup.

---

# 42. Fast troubleshooting sequence

When something is broken, use this order.

### Keycloak EC2

```bash
sudo docker ps -a
curl -I http://127.0.0.1:8081
sudo docker logs --tail=100 keycloak
sudo ss -lntp | grep 8081
```

### Kafka EC2

```bash
sudo docker ps -a
curl -I http://127.0.0.1:8080
sudo docker logs --tail=100 kafka
sudo docker logs --tail=100 kafka-ui
sudo ss -lntp | grep 8080
```

### Kafka EC2 to Keycloak private address

```bash
KEYCLOAK_PRIVATE_IP=$(terraform output -raw keycloak_private_ip)
```

If running this command from your local Terraform directory, use the returned address when connected to Kafka EC2:

```bash
curl -v http://KEYCLOAK_PRIVATE_IP:8081/realms/kafka-ui/.well-known/openid-configuration
```

If localhost works but private networking does not, inspect AWS networking.

If private networking works but browser access does not, inspect public security-group/EIP routing.

If networking works but OAuth login fails, inspect the OIDC URLs, redirect URI, client secret, and Keycloak/Kafka UI logs.

That separation prevents changing several unrelated settings at once.


## Fix: EC2 instance type not supported in the selected Availability Zone

If AWS reports an error similar to:

```text
Unsupported: Your requested instance type (t3.small) is not supported in your requested Availability Zone (us-east-1e).
```

the problem is **not Docker or Keycloak**. An AWS subnet belongs to exactly one Availability Zone, and not every EC2 instance type is offered in every AZ. If a subnet is created without an explicit AZ, AWS may place it in an AZ such as `us-east-1e`, even though one of the requested instance types cannot run there.

This project now avoids that problem automatically. Terraform queries the EC2 instance-type offerings for both configured instance types, finds the Availability Zones common to both, and creates the public subnet in the first common AZ.

The relevant logic is:

```hcl
data "aws_ec2_instance_type_offerings" "kafka" {
  filter {
    name   = "instance-type"
    values = [var.kafka_instance_type]
  }
  location_type = "availability-zone"
}

data "aws_ec2_instance_type_offerings" "keycloak" {
  filter {
    name   = "instance-type"
    values = [var.keycloak_instance_type]
  }
  location_type = "availability-zone"
}

locals {
  common_instance_azs = sort(tolist(setintersection(
    toset(data.aws_ec2_instance_type_offerings.kafka.locations),
    toset(data.aws_ec2_instance_type_offerings.keycloak.locations)
  )))

  selected_availability_zone = try(local.common_instance_azs[0], null)
}
```

The subnet then uses:

```hcl
availability_zone = local.selected_availability_zone
```

To see what Terraform selected:

```bash
terraform output selected_availability_zone
terraform output supported_common_availability_zones
```

For example, in one account the result may be:

```text
selected_availability_zone = "us-east-1a"
```

Do not assume the same letter mapping or offerings in every AWS account. Letting Terraform query the EC2 offerings is safer than permanently hard-coding an AZ.

### If an old subnet already exists in the bad AZ

Changing a subnet's Availability Zone requires replacing that subnet. Run:

```bash
terraform plan
```

You should see Terraform replace the public subnet and the EC2 resources that depend on it. For this lab that is expected. Then run:

```bash
terraform apply
```

If you want to rebuild only the lab and do not need any data on its EC2/EBS resources, a clean lab reset is also possible with:

```bash
terraform destroy
terraform apply
```

Do not use `destroy` if you have data you need to preserve.

## Keycloak H2 `AccessDeniedException` / restart loop

If Keycloak logs contain errors like:

```text
AccessDeniedException: /opt/keycloak/data/h2/keycloakdb.trace.db
Could not open file /opt/keycloak/data/h2/keycloakdb.mv.db
Failed to obtain JDBC connection
```

this is a Linux filesystem ownership problem. The official Keycloak container runs as UID `1000` (group `0`). If `/opt/keycloak/data/h2` is mounted from storage that is owned by root and is not writable by UID 1000, H2 cannot create or update its database files and Keycloak exits. Docker then restarts the container because the Compose service uses `restart: unless-stopped`.

This project now avoids that problem by using a bind-mounted host directory:

```text
/opt/keycloak-stack/keycloak-data/h2
        |
        +--> /opt/keycloak/data/h2 inside the container
```

The Keycloak bootstrap creates the directory and applies:

```bash
sudo chown -R 1000:0 /opt/keycloak-stack/keycloak-data
sudo chmod -R u+rwX,g+rwX /opt/keycloak-stack/keycloak-data
```

The systemd Compose service re-applies the ownership before every startup. The realm import file is also owned by `1000:0` and mode `0640`, because Keycloak must be able to read it while importing the realm.

### Repair an existing Keycloak EC2 without rebuilding it

If the existing instance is already running the old configuration, connect with SSM:

```bash
aws ssm start-session \
  --region us-east-1 \
  --target $(terraform output -raw keycloak_instance_id)
```

Then stop the restart loop:

```bash
cd /opt/keycloak-stack
sudo docker compose down
```

Create a writable host data directory:

```bash
sudo mkdir -p /opt/keycloak-stack/keycloak-data/h2
sudo chown -R 1000:0 /opt/keycloak-stack/keycloak-data
sudo chmod -R u+rwX,g+rwX /opt/keycloak-stack/keycloak-data
```

Make sure the realm file is readable by Keycloak:

```bash
sudo chown 1000:0 /opt/keycloak-stack/keycloak-realm.json
sudo chmod 640 /opt/keycloak-stack/keycloak-realm.json
```

Update the Keycloak volume in `docker-compose.yml` to:

```yaml
volumes:
  - ./keycloak-data/h2:/opt/keycloak/data/h2
  - ./keycloak-realm.json:/opt/keycloak/data/import/kafka-ui-realm.json:ro
```

Remove the old named volume if it is no longer needed. First see its exact name:

```bash
sudo docker volume ls
```

Then remove only the old Keycloak H2 volume after the container is down:

```bash
sudo docker volume rm <old-keycloak-volume-name>
```

Start Keycloak again:

```bash
sudo docker compose up -d
sudo docker compose ps
sudo docker compose logs -f keycloak
```

Verify the ownership from inside the container:

```bash
sudo docker exec keycloak sh -c 'id; ls -ld /opt/keycloak/data/h2; ls -la /opt/keycloak/data/h2'
```

You should see Keycloak running as UID `1000`, and `/opt/keycloak/data/h2` should be writable by that user.

Then test locally on the Keycloak EC2:

```bash
curl -i http://127.0.0.1:8081/realms/kafka-ui/.well-known/openid-configuration
```

A successful response proves the container and realm are running before you troubleshoot security groups, Elastic IPs, Kafka UI, or browser OIDC redirects.

### If you prefer a clean rebuild

Because EC2 user-data normally runs only on first boot, applying a changed Launch Template does not repair an already-running instance automatically. For a lab environment, replace the Keycloak EC2 so the corrected bootstrap runs from the beginning:

```bash
terraform apply -replace=aws_instance.keycloak
```

Then watch the bootstrap log through SSM:

```bash
sudo tail -f /var/log/keycloak-bootstrap.log
```
