# Kafka + Kafka UI + Keycloak on One AWS EC2 Instance

This project creates a **simple learning/lab environment** on AWS using Terraform.

It builds one EC2 instance and then Docker Compose starts:

- **Apache Kafka 4.3.1** in single-node KRaft mode
- **Kafbat Kafka UI v1.5.0**
- **Keycloak 26.7.3**
- A Keycloak realm named **`kafka-ui`**
- A Keycloak OpenID Connect client named **`kafka-ui`**
- A demo Keycloak user named **`kafkauser`** by default
- OAuth2 login from Kafka UI to Keycloak

The important idea is:

```text
Your Browser
     |
     | HTTP :8080
     v
+-------------------+
| Kafka UI          |
| Kafbat UI         |
+---------+---------+
          |
          | OAuth2 / OpenID Connect login
          v
+-------------------+
| Keycloak          |
| HTTP :8081        |
| realm: kafka-ui   |
| user: kafkauser   |
+-------------------+

Inside the EC2 Docker network:

+-------------------+       PLAINTEXT :9092       +-------------------+
| Kafka UI          | --------------------------> | Apache Kafka      |
+-------------------+                             | single-node KRaft |
                                                  +-------------------+
```

Kafka port `9092` is **not opened to the Internet**. Kafka UI talks to Kafka through Docker's private bridge network.

---

# 1. What this project is for

This is a good setup for:

- Learning Kafka
- Learning Kafka UI
- Testing Keycloak authentication
- Trying OAuth2 / OpenID Connect
- Creating topics and messages from a browser
- Testing Terraform + EC2 + Docker Compose

This is **not a production architecture**.

The lab intentionally uses:

- One EC2 server
- One Kafka broker/controller
- Keycloak `start-dev`
- Keycloak's local development database
- HTTP instead of HTTPS

Those choices make the lab easier to understand and cheaper than a production design.

---

# 2. Why `t3.medium` is the default

Kafka, Kafka UI, and Keycloak are all Java applications.

Java applications need memory.

A tiny EC2 instance may start, but it can quickly run out of RAM and Linux may kill one of the containers.

The default is:

```hcl
instance_type = "t3.medium"
```

That provides a much more realistic small lab host than a micro or nano instance.

You can experiment with a smaller instance later, but if containers disappear or restart, memory pressure is one of the first things to check.

---

# 3. Why there is an Elastic IP

OAuth login uses redirect URLs.

A simplified login looks like this:

```text
1. Browser opens Kafka UI

2. Kafka UI says:
      You must log in

3. Browser goes to Keycloak

4. User enters username/password

5. Keycloak redirects the browser back to Kafka UI
```

Keycloak only redirects to addresses that have been registered for the client.

For example:

```text
http://18.200.10.25:8080/login/oauth2/code/keycloak
```

A normal EC2 public IPv4 address can change when an instance is stopped and started.

This project therefore creates an **Elastic IP** so the OAuth callback address stays stable.

AWS charges for public IPv4 addresses, including Elastic IP addresses, so destroy the lab when you are finished.

---

# 4. AWS resources Terraform creates

Terraform creates:

```text
VPC
 |
 +-- Internet Gateway
 |
 +-- Public Subnet
      |
      +-- Route Table -> Internet Gateway
      |
      +-- EC2 Security Group
      |
      +-- EC2 t3.medium
           |
           +-- Elastic IP
           |
           +-- IAM role for SSM
           |
           +-- Docker
                |
                +-- Kafka
                +-- Kafka UI
                +-- Keycloak
```

It also creates:

- An EC2 IAM role
- An EC2 instance profile
- The `AmazonSSMManagedInstanceCore` policy attachment
- Random passwords for the Keycloak administrator and Kafka UI user
- A random OAuth client secret

---

# 5. Files in this project

```text
kafka-keycloak-ec2/
|
|-- main.tf
|-- terraform.tfvars.example
|-- README.md
|
|-- files/
|   |-- docker-compose.yml.tftpl
|   |-- kafka-ui.yml.tftpl
|   `-- keycloak-realm.json.tftpl
|
`-- templates/
    `-- user_data.sh.tftpl
```

## `main.tf`

Creates all AWS infrastructure.

It also renders the Docker Compose and authentication configuration files and sends them to EC2 as cloud-init user data.

## `terraform.tfvars.example`

Shows the easiest variables to change.

The most important one is:

```hcl
allowed_cidr = "YOUR.PUBLIC.IP.ADDRESS/32"
```

This controls which public IP can open Kafka UI and Keycloak.

## `files/docker-compose.yml.tftpl`

Defines the three containers:

```text
kafka
keycloak
kafka-ui
```

## `files/keycloak-realm.json.tftpl`

Automatically creates:

```text
Realm:  kafka-ui
Client: kafka-ui
User:   kafkauser
```

Keycloak imports this file the first time the realm is created.

## `files/kafka-ui.yml.tftpl`

Tells Kafka UI:

```text
Kafka broker = kafka:9092
Authentication = OAuth2
Identity provider = Keycloak
```

## `templates/user_data.sh.tftpl`

Runs when EC2 boots.

It:

1. Installs Docker.
2. Starts Docker.
3. Installs the Docker Compose plugin.
4. Writes the generated configuration files to `/opt/kafka-keycloak`.
5. Pulls the Docker images.
6. Starts the containers.

---

# 6. Prerequisites

You need these tools on your computer:

```text
Terraform
AWS CLI
```

Optional but strongly recommended:

```text
AWS Session Manager plugin
```

Check Terraform:

```bash
terraform version
```

Check AWS CLI:

```bash
aws --version
```

Check which AWS account you are using:

```bash
aws sts get-caller-identity
```

You should see your AWS account and ARN.

---

# 7. Configure AWS credentials

One common option is:

```bash
aws configure
```

Enter:

```text
AWS Access Key ID
AWS Secret Access Key
Default region
Output format
```

For this project the default region is:

```text
us-east-1
```

A better enterprise design is usually IAM Identity Center / SSO or role-based access instead of long-lived access keys.

---

# 8. Protect Kafka UI and Keycloak with your public IP

The example Terraform allows this variable:

```hcl
allowed_cidr
```

Copy the example file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit:

```hcl
allowed_cidr = "YOUR_PUBLIC_IP/32"
```

For example, if your Internet address were:

```text
68.32.112.68
```

use:

```hcl
allowed_cidr = "68.32.112.68/32"
```

The `/32` means:

> Allow exactly this one IPv4 address.

For a quick lab you can use:

```hcl
allowed_cidr = "0.0.0.0/0"
```

but that means:

> Allow every IPv4 address on the Internet to reach ports 8080 and 8081.

That is easier for testing but less safe.

---

# 9. Initialize Terraform

From the project directory:

```bash
terraform init
```

This downloads the Terraform providers.

Validate the configuration:

```bash
terraform validate
```

Format the Terraform file:

```bash
terraform fmt
```

---

# 10. Preview what Terraform will create

Run:

```bash
terraform plan
```

Terraform will show resources with a `+` sign.

Think of `terraform plan` as a preview before Terraform changes AWS.

---

# 11. Create the environment

Run:

```bash
terraform apply
```

Review the plan and enter:

```text
yes
```

Terraform creates the AWS infrastructure and returns outputs.

Useful outputs include:

```text
kafka_ui_url
keycloak_url
keycloak_admin_url
public_ip
ssm_start_session
```

---

# 12. Get the Kafka UI URL

Run:

```bash
terraform output -raw kafka_ui_url
```

Example:

```text
http://18.200.10.25:8080
```

Open that URL in your browser.

Kafka UI should require Keycloak login.

---

# 13. Get the Kafka UI username and password

Username:

```bash
terraform output -raw kafka_ui_username
```

Default:

```text
kafkauser
```

Password:

```bash
terraform output -raw kafka_ui_user_password
```

The password is generated by Terraform.

Do not expect to see sensitive Terraform outputs in the normal output listing. Use `terraform output -raw` for the specific value.

---

# 14. Kafka UI login flow

When you open:

```text
http://ELASTIC-IP:8080
```

Kafka UI should redirect you to Keycloak.

The Keycloak realm is:

```text
kafka-ui
```

Log in with:

```text
Username: kafkauser
Password: use terraform output -raw kafka_ui_user_password
```

After authentication, Keycloak redirects the browser to:

```text
http://ELASTIC-IP:8080/login/oauth2/code/keycloak
```

Kafka UI exchanges the authorization code with Keycloak and creates your authenticated UI session.

---

# 15. Why Kafka UI uses two kinds of Keycloak addresses

This is one of the most important parts of this configuration.

There are two paths.

## Front channel

The **browser** must be able to reach Keycloak.

Therefore Kafka UI uses the EC2 Elastic IP for the authorization page:

```text
http://ELASTIC-IP:8081/realms/kafka-ui/protocol/openid-connect/auth
```

## Back channel

Kafka UI itself is a Docker container.

It can talk directly to the Keycloak container over Docker networking:

```text
http://keycloak:8080
```

Therefore token, key, and user-information requests use the Docker service name.

Example:

```text
http://keycloak:8080/realms/kafka-ui/protocol/openid-connect/token
```

This avoids sending internal service-to-service OAuth traffic out through the public Internet path.

---

# 16. Open the Keycloak Admin Console

Get the URL:

```bash
terraform output -raw keycloak_admin_url
```

Get the admin username:

```bash
terraform output -raw keycloak_admin_username
```

Get the generated password:

```bash
terraform output -raw keycloak_admin_password
```

Open the admin URL and log in.

The administrator initially belongs to the Keycloak `master` realm.

After login, use the realm selector and choose:

```text
kafka-ui
```

You should see:

```text
Clients
  kafka-ui

Users
  kafkauser
```

---

# 17. Connect to EC2 without SSH

This project does not open port 22.

Instead it attaches the AWS-managed SSM policy to EC2.

Get the command:

```bash
terraform output -raw ssm_start_session
```

It will look similar to:

```bash
aws ssm start-session \
  --region us-east-1 \
  --target i-0123456789abcdef0
```

If AWS CLI reports:

```text
SessionManagerPlugin is not found
```

install the AWS Session Manager plugin on your local computer and run the command again.

---

# 18. Check cloud-init

After connecting with SSM:

```bash
sudo cloud-init status
```

To wait for first-boot configuration to finish:

```bash
sudo cloud-init status --wait
```

View the startup log:

```bash
sudo less /var/log/cloud-init-output.log
```

Follow it live:

```bash
sudo tail -f /var/log/cloud-init-output.log
```

---

# 19. Find the Docker Compose files on EC2

The generated files are stored here:

```text
/opt/kafka-keycloak
```

View them:

```bash
sudo ls -la /opt/kafka-keycloak
```

You should see:

```text
docker-compose.yml
kafka-ui.yml
keycloak-realm.json
```

---

# 20. Check the containers

Run:

```bash
cd /opt/kafka-keycloak
sudo docker compose ps
```

Expected containers:

```text
kafka
kafka-ui
keycloak
```

Also try:

```bash
sudo docker ps
```

---

# 21. View Kafka logs

```bash
cd /opt/kafka-keycloak
sudo docker compose logs kafka
```

Follow them:

```bash
sudo docker compose logs -f kafka
```

---

# 22. View Kafka UI logs

```bash
cd /opt/kafka-keycloak
sudo docker compose logs kafka-ui
```

Follow them:

```bash
sudo docker compose logs -f kafka-ui
```

OAuth configuration errors are usually visible here.

---

# 23. View Keycloak logs

```bash
cd /opt/kafka-keycloak
sudo docker compose logs keycloak
```

Follow them:

```bash
sudo docker compose logs -f keycloak
```

Look for messages showing that the `kafka-ui` realm was imported.

---

# 24. Verify Kafka directly

List topics from inside the Kafka container:

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --list
```

If that command works, the broker is accepting Kafka connections.

---

# 25. Create a Kafka topic from the command line

Create a topic named `demo`:

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --create \
  --topic demo \
  --partitions 1 \
  --replication-factor 1
```

List topics again:

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --list
```

You should see:

```text
demo
```

Refresh Kafka UI and the topic should appear there too.

---

# 26. Produce a test message

Run:

```bash
echo 'hello from kafka' | \
sudo docker exec -i kafka \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 \
  --topic demo
```

That sends one message to the `demo` topic.

---

# 27. Consume the test message

Run:

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic demo \
  --from-beginning \
  --max-messages 1
```

Expected text:

```text
hello from kafka
```

You can also open the topic in Kafka UI and inspect its messages.

---

# 28. How Kafka networking works here

Docker creates a private network named:

```text
kafka-keycloak-appnet
```

Docker Compose service names become DNS names inside that network.

That means Kafka UI can use:

```text
kafka:9092
```

instead of needing the EC2 public IP.

Keycloak can be reached internally as:

```text
keycloak:8080
```

This is why Kafka port 9092 does not need a public security-group rule.

---

# 29. Kafka KRaft mode explained simply

Older Kafka deployments commonly used ZooKeeper.

Modern Kafka can use **KRaft** instead.

KRaft lets Kafka manage its cluster metadata without ZooKeeper.

This lab makes the same Kafka process both:

```text
broker
controller
```

The important Docker variables include:

```yaml
KAFKA_PROCESS_ROLES: "broker,controller"
KAFKA_NODE_ID: "1"
KAFKA_CONTROLLER_QUORUM_VOTERS: "1@kafka:9093"
```

Because there is only one Kafka node, replication-related values are set to `1`.

That is appropriate for a lab but not for high availability.

---

# 30. Keycloak realm import explained

The Docker Compose configuration mounts:

```text
keycloak-realm.json
```

into:

```text
/opt/keycloak/data/import/kafka-ui-realm.json
```

Keycloak starts with:

```text
start-dev --import-realm
```

That tells Keycloak:

> When starting, look in the import directory and create any realm that does not already exist.

An important Keycloak behavior is that startup import does **not overwrite an existing realm**.

This protects an existing realm from being silently replaced on every restart.

If you change the realm JSON later and expect it to replace the current realm, you must deliberately delete/re-import the realm or rebuild the Keycloak development data.

---

# 31. Kafka UI OAuth configuration explained

The important part is:

```yaml
auth:
  type: OAUTH2
```

That tells Kafka UI:

> Do not use the UI until the user authenticates through an OAuth2 provider.

The configured provider is Keycloak:

```yaml
clientId: kafka-ui
provider: keycloak
scope: openid
```

OpenID Connect is built on OAuth2 and adds identity information about the logged-in user.

The username claim is:

```yaml
user-name-attribute: preferred_username
```

For the imported demo user, that becomes:

```text
kafkauser
```

---

# 32. Why Kafka itself has no Keycloak login

This project protects **Kafka UI** with Keycloak.

It does not configure Kafka broker authentication with Keycloak.

The architecture is:

```text
User
 |
 | Keycloak login
 v
Kafka UI
 |
 | internal plaintext Kafka connection
 v
Kafka
```

That is simpler for learning.

A production Kafka cluster normally has its own broker-level authentication and encryption, such as:

- SASL/SCRAM
- mTLS
- SASL/OAUTHBEARER
- AWS MSK IAM authentication

Do not assume protecting Kafka UI automatically protects a publicly exposed Kafka broker. This project avoids that problem by not exposing Kafka's broker port publicly at all.

---

# 33. Restart all containers

```bash
cd /opt/kafka-keycloak
sudo docker compose restart
```

---

# 34. Stop the containers

```bash
cd /opt/kafka-keycloak
sudo docker compose stop
```

---

# 35. Start the containers again

```bash
cd /opt/kafka-keycloak
sudo docker compose start
```

---

# 36. Re-create the containers

```bash
cd /opt/kafka-keycloak
sudo docker compose up -d
```

---

# 37. Pull images again

```bash
cd /opt/kafka-keycloak
sudo docker compose pull
sudo docker compose up -d
```

The project pins Kafka and Keycloak versions. Kafka UI is also pinned to `v1.5.0` in the supplied compose template for repeatability.

---

# 38. Troubleshooting: browser cannot connect to port 8080 or 8081

First check Terraform output:

```bash
terraform output public_ip
```

Then verify the security group allows your current Internet IP.

If you changed networks, your home/office public IP may have changed.

For a temporary test you can change:

```hcl
allowed_cidr = "0.0.0.0/0"
```

and run:

```bash
terraform apply
```

If it works afterward, your previous CIDR was probably wrong.

Change it back to your `/32` once you know the correct address.

---

# 39. Troubleshooting: EC2 exists but containers are missing

Connect with SSM and run:

```bash
sudo cloud-init status
sudo tail -200 /var/log/cloud-init-output.log
```

Then:

```bash
sudo systemctl status docker
```

Check Docker Compose:

```bash
sudo docker compose version
```

Check files:

```bash
sudo ls -la /opt/kafka-keycloak
```

Try manually:

```bash
cd /opt/kafka-keycloak
sudo docker compose config
sudo docker compose pull
sudo docker compose up -d
```

---

# 40. Troubleshooting: Kafka UI loads but cannot see Kafka

Run:

```bash
cd /opt/kafka-keycloak
sudo docker compose logs kafka-ui
```

Then check Kafka:

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --list
```

Also inspect the Kafka UI configuration:

```bash
sudo cat /opt/kafka-keycloak/kafka-ui.yml
```

You should see:

```yaml
bootstrapServers: kafka:9092
```

---

# 41. Troubleshooting: Keycloak page loads but Kafka UI login fails

Check both logs:

```bash
cd /opt/kafka-keycloak
sudo docker compose logs kafka-ui
sudo docker compose logs keycloak
```

Check the callback URL in the generated realm file:

```bash
sudo grep -n "redirect" /opt/kafka-keycloak/keycloak-realm.json
```

It should use the same Elastic IP shown by:

```bash
terraform output -raw public_ip
```

The callback should look like:

```text
http://ELASTIC-IP:8080/login/oauth2/code/keycloak
```

---

# 42. Troubleshooting: `invalid_redirect_uri`

This means Keycloak received an OAuth request containing a callback address that does not match what the client allows.

Check:

```bash
terraform output -raw public_ip
```

Then open the Keycloak Admin Console:

```text
Realm: kafka-ui
Clients
kafka-ui
Valid redirect URIs
```

Expected value:

```text
http://ELASTIC-IP:8080/login/oauth2/code/keycloak
```

---

# 43. Troubleshooting: realm changes do not appear

Keycloak skips startup import if the realm already exists.

For a disposable lab, one clean reset is:

```bash
cd /opt/kafka-keycloak
sudo docker compose down -v
sudo docker compose up -d
```

**Warning:** `-v` deletes the Docker volumes for this lab. Kafka data and Keycloak development data will be removed.

Use this only when you intentionally want a clean lab reset.

---

# 44. Check memory problems

Run:

```bash
free -h
```

Check container usage:

```bash
sudo docker stats
```

Check whether Linux killed a process because of low memory:

```bash
sudo dmesg | grep -i -E 'oom|out of memory|killed process'
```

If you see out-of-memory messages, increase the EC2 size.

Example:

```hcl
instance_type = "t3.large"
```

Then:

```bash
terraform apply
```

Depending on the Terraform change, the instance may be stopped/restarted or replaced, so review the plan carefully first.

---

# 45. Security notes

This configuration is intentionally easy to learn from, not hardened for production.

Important limitations:

1. Kafka UI uses HTTP.
2. Keycloak uses HTTP.
3. Keycloak uses `start-dev`.
4. Keycloak uses its local development database.
5. Kafka is a one-node cluster.
6. Kafka's Docker-network connection uses PLAINTEXT.
7. Terraform-generated passwords and OAuth client secrets are stored in Terraform state.
8. Opening `allowed_cidr = "0.0.0.0/0"` exposes Kafka UI and Keycloak to the Internet.

For anything beyond a lab, use HTTPS and a proper secret-management design.

---

# 46. What a more production-ready design looks like

A stronger design would normally separate the components.

Example:

```text
Internet
   |
   v
HTTPS ALB
   |
   +----------------------+
   |                      |
   v                      v
Kafka UI               Keycloak
private compute        private compute
                          |
                          v
                    RDS PostgreSQL

Kafka applications
   |
   v
Amazon MSK or multi-node Kafka
```

Production improvements include:

- HTTPS certificates
- Application Load Balancer or another reverse proxy
- Private subnets
- Keycloak backed by PostgreSQL/RDS
- Multiple Keycloak instances if high availability is needed
- Amazon MSK or multiple Kafka brokers/controllers
- Kafka encryption/authentication
- AWS Secrets Manager or SSM Parameter Store for secrets
- CloudWatch logs/metrics
- Backups
- Auto Scaling where appropriate
- Least-privilege IAM

---

# 47. Destroy the lab

When you are finished:

```bash
terraform destroy
```

Review the destroy plan carefully.

Enter:

```text
yes
```

Terraform should remove:

- EC2
- Elastic IP
- VPC networking
- Security group
- IAM role/profile created by this project
- EBS root volume

Destroying the lab is important because EC2, EBS, and public IPv4 resources can continue creating AWS charges while they exist.

---

# 48. Quick command cheat sheet

## Create

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

## URLs

```bash
terraform output -raw kafka_ui_url
terraform output -raw keycloak_url
terraform output -raw keycloak_admin_url
```

## User credentials

```bash
terraform output -raw kafka_ui_username
terraform output -raw kafka_ui_user_password
```

## Keycloak administrator

```bash
terraform output -raw keycloak_admin_username
terraform output -raw keycloak_admin_password
```

## SSM

```bash
terraform output -raw ssm_start_session
```

## Containers

```bash
cd /opt/kafka-keycloak
sudo docker compose ps
sudo docker compose logs -f kafka
sudo docker compose logs -f kafka-ui
sudo docker compose logs -f keycloak
```

## Kafka topic

```bash
sudo docker exec kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --list
```

## Destroy

```bash
terraform destroy
```

---

# 49. Official references

These are useful background references for the technologies used by this project.

## Apache Kafka Docker

https://kafka.apache.org/43/getting-started/docker/

## Apache Kafka Docker examples

https://github.com/apache/kafka/tree/trunk/docker/examples

## Kafbat Kafka UI

https://github.com/kafbat/kafka-ui

## Kafbat OAuth2 authentication

https://ui.docs.kafbat.io/configuration/authentication/for-the-ui/oauth2

## Kafbat configuration file

https://ui.docs.kafbat.io/configuration/configuration-file

## Keycloak containers

https://www.keycloak.org/server/containers

## Keycloak realm import/export

https://www.keycloak.org/server/importExport

## Keycloak hostname configuration

https://www.keycloak.org/server/hostname

## AWS Docker on Amazon Linux 2023

https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-docker.html

## Docker Compose plugin

https://docs.docker.com/compose/install/linux/

---

# Final learning summary

The most important concepts in this lab are:

```text
Terraform
   creates AWS infrastructure

EC2
   provides one Linux computer

Docker Compose
   runs multiple applications on that computer

Kafka
   stores and moves event messages

Kafka UI
   gives you a browser interface to Kafka

Keycloak
   authenticates the person using Kafka UI

OAuth2 / OpenID Connect
   lets Kafka UI trust the Keycloak login

Docker networking
   lets containers use names such as kafka and keycloak
   instead of public IP addresses

SSM
   lets you administer EC2 without opening SSH to the Internet
```

That separation is useful to remember because each layer solves a different problem.
