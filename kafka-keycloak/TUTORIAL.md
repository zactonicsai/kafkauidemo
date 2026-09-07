# Kafka + Kafka UI + Keycloak with Docker Compose — Step-by-Step Tutorial

**What you will build:** a little "message post office" (Kafka), a website to look inside it (Kafka UI), and a security guard at the door of that website (Keycloak). Everything runs on your own computer with one command.

**Versions used (current as of September 2026):**

| Piece | Image | Why this one |
|---|---|---|
| Apache Kafka | `apache/kafka:4.3.1` | Official image, newest supported release, KRaft mode (no ZooKeeper) |
| Keycloak | `quay.io/keycloak/keycloak:26.7` | Newest supported line (26.7.x) |
| Kafka UI | `ghcr.io/kafbat/kafka-ui:v1.5.0` | Kafbat is the actively maintained successor of the old Provectus `kafka-ui` |

---

## Part 1 — Quick Setup (do this first)

### Step 0: What you need

* **Docker Desktop** (Windows/Mac) or **Docker Engine + Compose plugin** (Linux). Check it works:
  ```bash
  docker --version
  docker compose version
  ```
* About **2 GB of free RAM** for the three containers.
* Ports **8080**, **8090** and **29092** free on your computer.

### Step 1: Create the folder layout

Make a folder called `kafka-keycloak` with this structure (all four files are included with this tutorial):

```
kafka-keycloak/
├── docker-compose.yml          <- starts the 3 containers
├── keycloak/
│   └── realm-kafka.json        <- pre-made users, roles and app settings for Keycloak
└── kafka-ui/
    ├── config.yml              <- Kafka UI settings (login via Keycloak)
    └── config-rbac.yml         <- optional: same, plus admin / read-only roles
```

### Step 2: Start everything

Open a terminal **inside** the `kafka-keycloak` folder and run:

```bash
docker compose up -d
```

The first time this downloads about 1.5 GB of images, so it can take a few minutes. Watch progress with:

```bash
docker compose logs -f
```

Press `Ctrl + C` to stop watching (the containers keep running). You are ready when you see:

* Kafka: `Kafka Server started`
* Keycloak: `Keycloak 26.7.x on JVM ... started` and `Realm 'kafka' imported`
* Kafka UI: `Started KafkaUiApplication`

Check all three are healthy:

```bash
docker compose ps
```

### Step 3: Log in to Kafka UI through Keycloak

1. Open **http://localhost:8090** in your browser.
2. You will see a login page with one button: **Keycloak**. Click it.
3. Your browser jumps to Keycloak at `http://localhost:8080/realms/kafka/...`.
4. Sign in with:
   * username **`alice`**, password **`alice`**
5. Keycloak sends you back to Kafka UI, now logged in. Your name (`alice`) shows in the top-right corner.

That is the whole login flow working. 🎉

### Step 4: Put a message into Kafka and see it in the UI

Send a few messages from the command line (this runs *inside* the Kafka container):

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic demo
```

Type a few lines, e.g. `hello`, `world`, then press `Ctrl + C`.

Now in Kafka UI: **Topics → demo → Messages**. Your lines are there.

Read them back from the command line too:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic demo --from-beginning
```

### Step 5: Look at Keycloak's admin console

* Open **http://localhost:8080**, click **Administration Console**.
* Log in with **`admin` / `admin`**.
* In the top-left dropdown, switch from realm **master** to realm **kafka**.
* Click **Users** — you'll see `alice` and `bob`. Click **Clients** — you'll see `kafka-ui`.

This was all created automatically from `keycloak/realm-kafka.json`.

### Step 6 (optional): Turn on roles — admin vs read-only

Right now *anyone* with a Keycloak account gets full power in Kafka UI. Let's make `alice` an admin and `bob` a viewer.

1. In `docker-compose.yml`, in the `kafka-ui` service, change the volume line:
   ```yaml
       volumes:
         - ./kafka-ui/config-rbac.yml:/config.yml:ro
   ```
2. Recreate just the UI container:
   ```bash
   docker compose up -d --force-recreate kafka-ui
   ```
3. Log out of Kafka UI (top-right menu) and log in as **`bob` / `bob`**. Bob can open topics and read messages, but the **Add a Topic** and **Produce Message** buttons are gone.
4. Log in as `alice` again — everything is back.

> **Tip: "Log out" only ends the Kafka UI session.** Keycloak still remembers you in a cookie, so clicking the Keycloak button again logs you straight back in as the same person. To switch users, also visit http://localhost:8080/realms/kafka/protocol/openid-connect/logout, or use a private browser window.

### Step 7: Stop / reset

```bash
docker compose down          # stop, keep data (topics, Keycloak users)
docker compose down -v       # stop AND delete all data (fresh start next time)
```

---

## Part 2 — What just happened? (Background)

### Kafka in one paragraph

Kafka is a **log of messages**. Programs called *producers* append messages to named streams called **topics**; programs called *consumers* read them, and Kafka remembers how far each consumer got (its *offset*). Topics are split into **partitions** so many machines can share the work, and each partition can be copied to several brokers (the *replication factor*) for safety. Since Kafka 4.0, the cluster manages itself with a built-in protocol called **KRaft**; the old ZooKeeper helper program is gone.

### Keycloak in one paragraph

Keycloak is an **identity provider**. Instead of every app keeping its own list of usernames and passwords, apps ask Keycloak "who is this person and what roles do they have?" It speaks the standard protocols **OpenID Connect (OIDC)** and **OAuth 2.0**. Its main ideas:

* **Realm** — a completely separate space with its own users and apps. We made one called `kafka` (never use `master` for apps; it's for administering Keycloak itself).
* **Client** — an application that is allowed to ask Keycloak to log people in. Ours is `kafka-ui`.
* **Roles** — labels on users (`kafka-admin`, `kafka-viewer`).
* **Token** — a signed piece of JSON (a *JWT*) that Keycloak hands to the app saying "this is alice, she has these roles, and this is valid for 5 minutes".

### Kafka UI in one paragraph

Kafbat UI is a web dashboard for Kafka: browse brokers, topics, messages, consumer groups, schemas and connectors. It is a Java (Spring Boot) app, so its login system is **Spring Security**, which is why its config keys look like `issuer-uri`, `jwk-set-uri`, etc.

### The login dance (Authorization Code flow)

```
 Browser                Kafka UI (container)          Keycloak (container)
   |  1. open :8090         |                              |
   |----------------------->|                              |
   |  2. redirect to Keycloak login page (localhost:8080)  |
   |<-----------------------|                              |
   |  3. user types alice/alice                            |
   |------------------------------------------------------>|
   |  4. redirect back to :8090/login/oauth2/code/keycloak?code=XYZ
   |<------------------------------------------------------|
   |  5. hand the code to Kafka UI                         |
   |----------------------->|                              |
   |                        | 6. swap code+secret for tokens (keycloak:8080)
   |                        |----------------------------->|
   |                        | 7. verify token signature (jwk-set-uri)
   |                        |----------------------------->|
   |  8. logged in!         |                              |
   |<-----------------------|                              |
```

Steps 2–4 happen in your **browser**, so they must use `localhost:8080`. Steps 6–7 happen **container-to-container**, so they use the Docker service name `keycloak:8080`. That is the single most common thing people get wrong, and it's why `config.yml` spells out every URL instead of using one `issuer-uri`.

---

## Part 3 — The files explained line by line

### `docker-compose.yml`

**Kafka service**

| Setting | Meaning |
|---|---|
| `KAFKA_PROCESS_ROLES: broker,controller` | One container does both jobs ("combined mode"). Fine for dev; in production you run separate controllers. |
| `KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093` | The list of controllers that vote. Only one here. |
| `KAFKA_LISTENERS` / `KAFKA_ADVERTISED_LISTENERS` | *Listeners* are the doors Kafka opens. *Advertised* listeners are the addresses Kafka **tells clients to use**. Containers use `kafka:9092`, your laptop uses `localhost:29092`. If a client connects and Kafka advertises an address the client can't reach, you get the famous "connected then timed out" problem. |
| `*_REPLICATION_FACTOR: 1` | Internal topics normally want 3 copies; with one broker that's impossible, so we say 1. |
| `healthcheck` | Compose waits until Kafka answers API calls before starting Kafka UI. |

**Keycloak service**

| Setting | Meaning |
|---|---|
| `start-dev --import-realm` | Dev mode (plain HTTP, built-in H2 database, any hostname allowed) and "load any JSON in `/opt/keycloak/data/import` on first boot". |
| `KC_BOOTSTRAP_ADMIN_USERNAME/PASSWORD` | Creates the first admin. (Keycloak 26 renamed the old `KEYCLOAK_ADMIN` variables.) |
| `KC_HEALTH_ENABLED` | Exposes `/health` on the management port 9000 inside the container. |
| `keycloak-data` volume | Keeps the H2 database so users you add by hand survive restarts. |

**Kafka UI service**

| Setting | Meaning |
|---|---|
| `8090:8080` | Kafka UI listens on 8080 *inside* its container, but Keycloak already took 8080 on your laptop, so we expose it as 8090. |
| `SPRING_CONFIG_ADDITIONAL-LOCATION: /config.yml` | Tells Spring Boot to read our mounted YAML. |
| `KEYCLOAK_CLIENT_SECRET` | Injected into the YAML with `${KEYCLOAK_CLIENT_SECRET:kafka-ui-secret}` (the part after `:` is the default). |

### `keycloak/realm-kafka.json`

* `"sslRequired": "none"` — allow plain HTTP; **dev only**.
* Client `kafka-ui`:
  * `"publicClient": false` + `"secret"` — a *confidential* client: Kafka UI proves who it is with a secret when swapping the code for tokens.
  * `"standardFlowEnabled": true` — enables the Authorization Code flow. Implicit flow and direct grants are **off** (best practice).
  * `"redirectUris": ["http://localhost:8090/*"]` — Keycloak refuses to send users back to any other address. This blocks a classic attack.
  * `"pkce.code.challenge.method": ""` — Kafbat UI v1.5.0 does not send PKCE yet (open issue #1721), so if you force S256 here, login fails with `Missing parameter: code_challenge_method`.
  * The `realm-roles-flat` mapper copies the user's realm roles into a top-level claim called **`roles`**. Keycloak's default puts roles under `realm_access.roles`, and Kafka UI's `roles-field` cannot read nested fields, so this mapper is required for RBAC.
* Users `alice` and `bob` with `"temporary": false` passwords (otherwise Keycloak asks them to change it on first login).

### `kafka-ui/config.yml`

| Key | Meaning |
|---|---|
| `auth.type: OAUTH2` | Switch login mode from "none" / "LOGIN_FORM" to OAuth2. |
| `client.keycloak` | The registration id. It appears in the callback URL `/login/oauth2/code/keycloak`. |
| `authorization-uri` | Browser goes here → `localhost`. |
| `token-uri`, `user-info-uri`, `jwk-set-uri` | Server goes here → `keycloak`. |
| `user-name-attribute: preferred_username` | Which claim to show as the user's name (`alice`). |
| `custom-params.type: oauth` | Generic OIDC provider handling. |
| `custom-params.roles-field: roles` | Which claim holds roles (matches our mapper). |

### `kafka-ui/config-rbac.yml`

Adds an `rbac.roles` list. Each role has:

* `subjects` — who gets it (`provider: oauth`, `type: role`, `value: kafka-admin` = "users whose `roles` claim contains `kafka-admin`").
* `clusters` — which clusters it applies to.
* `permissions` — resource + regex (`value: ".*"` = all) + actions (`all`, or a list like `[view, messages_read]`).

**Important:** the moment an `rbac:` block exists, users with **no matching role see nothing** (a blank cluster list). If you log in and see nothing, that's RBAC working — the user just has no role.

---

## Part 4 — Best practices

1. **Never use `master` realm for apps.** Make a realm per project.
2. **Confidential client + Authorization Code flow** for server-side apps like Kafka UI. Keep implicit flow and direct-access grants off.
3. **Exact redirect URIs.** `http://localhost:8090/*` is fine on a laptop; in production use the full callback, e.g. `https://kafka-ui.example.com/login/oauth2/code/keycloak`, no wildcard.
4. **Secrets out of files.** Put the real secret in a `.env` file (`KEYCLOAK_CLIENT_SECRET=...`), add `.env` to `.gitignore`, and reference it from compose with `${KEYCLOAK_CLIENT_SECRET}`.
5. **Pin image versions** (we did). `latest` can silently change and break your config overnight.
6. **Use RBAC** so that only admins can create or delete topics. Give humans roles, not permissions; map roles in one place.
7. **Production Keycloak means `start`, not `start-dev`:** real database (PostgreSQL), HTTPS, and a fixed hostname (`KC_HOSTNAME=https://auth.example.com`). Dev mode is explicitly unsafe for production.
8. **Short token lifetimes** (we used 5 minutes) — a stolen token becomes useless quickly.
9. **Protect Kafka too.** This tutorial secures the *dashboard*, not the *broker*. Anyone on your network can still talk to `localhost:29092`. For a real cluster enable SASL (Kafka can also verify Keycloak tokens directly with the `OAUTHBEARER` mechanism) and TLS.
10. **Healthchecks + `depends_on: condition`** so containers start in the right order and you don't chase phantom "connection refused" errors.

---

## Part 5 — Options, pros and cons

### Kafka UI login options

| Option | Pros | Cons |
|---|---|---|
| **No auth** (`auth.type: DISABLED`) | Zero setup | Anyone can delete your topics |
| **LOGIN_FORM** (users in YAML) | Simple, no extra service | Passwords in a file, no SSO, no roles from a central place |
| **LDAP / Active Directory** | Reuses company directory | Needs LDAP knowledge; no modern MFA out of the box |
| **OAuth2 / OIDC with Keycloak** (this tutorial) | Central users, SSO, MFA, roles, audit logs | One more service to run; URL/redirect details are fiddly |
| **OAuth2 with Google / GitHub / Azure / Okta** | No identity server to host | Depends on a cloud provider; roles need extra setup |

### Ways to solve the "two hostnames" problem

| Approach | Pros | Cons |
|---|---|---|
| **Explicit URIs** (what we did) | Works on any OS, no host changes, no Keycloak hostname config | Longer config; ID-token issuer isn't cross-checked |
| **Add `127.0.0.1 keycloak` to your hosts file** and use a single `issuer-uri: http://keycloak:8080/realms/kafka` | Shortest config; full OIDC discovery and issuer validation | Every developer must edit `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts`) |
| **Real DNS + reverse proxy** (production) | Same URL everywhere, HTTPS | Only makes sense beyond a laptop |

### Kafka image choices

| Image | Pros | Cons |
|---|---|---|
| `apache/kafka` (JVM) | Official, all tools included (`kafka-console-producer.sh` etc.) | ~500 MB |
| `apache/kafka-native` (GraalVM) | Starts in under a second, small | Fewer bundled tools; less common in tutorials |
| `confluentinc/cp-kafka` | Ships with Confluent extras (Schema Registry etc.) | Larger, Confluent's env-var naming, license terms to read |
| `bitnami/kafka` | Long-standing, many examples online | Bitnami changed its free-image policy in 2025; check availability |

### Single-node vs multi-node

Single combined node = perfect for learning, useless for real fault tolerance. For a realistic dev cluster, run 3 brokers and set replication factors to 3.

---

## Part 6 — Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Browser shows `keycloak:8080` can't be reached | `authorization-uri` uses the Docker name | Must be `localhost:8080` (browser-facing) |
| Kafka UI log: `Connection refused ... localhost:8080` | A server-side URI uses `localhost` | `token-uri`, `user-info-uri`, `jwk-set-uri` must use `keycloak:8080` |
| Keycloak page: **Invalid parameter: redirect_uri** | Client's *Valid redirect URIs* doesn't match | Must include `http://localhost:8090/*` |
| `Missing parameter: code_challenge_method` | PKCE forced on the client | In Keycloak → Clients → kafka-ui → Advanced, set PKCE method to *(blank)* |
| Login works but cluster list is empty | RBAC on and user has no matching role | Check the `roles` claim (Keycloak → Clients → kafka-ui → Client scopes → Evaluate) |
| `[invalid_client] Invalid client or Invalid client credentials` | Secret mismatch | Compare `KEYCLOAK_CLIENT_SECRET` with the client secret in Keycloak |
| Port 8080 already in use | Something else on your laptop uses it | Change Keycloak to `"8081:8080"` **and** every `localhost:8080` in `config.yml` and `realm-kafka.json` |
| Realm didn't import | Volume already had data from an earlier run | `docker compose down -v` then `up -d` (import only runs on an empty database) |
| Kafka UI shows cluster **offline** | Kafka still starting | Wait for the healthcheck; `docker compose logs kafka` |

Useful commands:

```bash
docker compose logs -f kafka-ui           # watch the UI's login errors
docker compose logs -f keycloak           # watch Keycloak
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

---

## Part 7 — Going further

* **Let Kafka itself trust Keycloak:** configure the broker listener with `sasl.enabled.mechanisms=OAUTHBEARER` and `sasl.oauthbearer.jwks.endpoint.url=http://keycloak:8080/realms/kafka/protocol/openid-connect/certs`; then producers/consumers log in with Keycloak client credentials instead of plaintext.
* **Add Schema Registry and Kafka Connect** — Kafbat UI has tabs for both; just add `schemaRegistry:` and `kafkaConnect:` under the cluster in `config.yml`.
* **Groups instead of roles** — in Keycloak create groups, add a *Group Membership* mapper with claim name `groups`, and set `roles-field: groups`.
* **HTTPS everywhere** — put Traefik or Caddy in front of both Keycloak and Kafka UI and switch every `http://` to `https://`.

## References

* Kafbat UI docs — OAuth2 providers: https://ui.docs.kafbat.io/configuration/authentication/oauth2
* Kafbat UI docs — RBAC: https://ui.docs.kafbat.io/configuration/rbac-role-based-access-control
* Keycloak server configuration guides: https://www.keycloak.org/guides
* Apache Kafka Docker image docs: https://kafka.apache.org/documentation/#docker
