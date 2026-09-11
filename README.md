# Homepage + Traefik + Let's Encrypt on Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This repository deploys Homepage (a fast, configuration-driven dashboard for everything you self-host, with live status widgets) behind Traefik with automatic Let's Encrypt TLS.

## Getting started

```bash
# 1. Clone
git clone https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose
cd homepage-traefik-letsencrypt-docker-compose

# 2. Create the two Docker networks the stack expects
docker network create traefik-network
docker network create homepage-network

# 3. Copy the environment template and fill in required values
cp .env.example .env
$EDITOR .env
# ^ Required: HOMEPAGE_HOSTNAME, TRAEFIK_HOSTNAME,
#   TRAEFIK_ACME_EMAIL, TRAEFIK_BASIC_AUTH.

# 4. Deploy
docker compose -f homepage-traefik-letsencrypt-docker-compose.yml -p homepage up -d

# 5. Edit your dashboard. The files were seeded on the first start.
$EDITOR config/services.yaml
```

Homepage re-reads the directory as you save, so step 5 is a loop, not a step.

### Your configuration is yours, and git never touches it

Homepage is configured by hand-written YAML, which means the config directory belongs to you and not to this repository. If it were tracked in git, every `git pull` would collide with your edits — and `update.sh`, which refuses to run over local changes, would refuse to run at all.

So the starting point ships as `config.example/`, an init container copies it into an empty config directory once, and the directory itself is gitignored. Nothing is ever overwritten: the seeding container checks whether the directory has any files, and if it does, it says so and stops. New options arrive in `config.example/` after an update, where you can read them and copy across what you want.

CI asserts this both ways — that an empty directory gets seeded, and that a second run leaves an edited file byte-for-byte alone along with files `config.example` has never heard of.

### What success looks like

```bash
docker compose -f homepage-traefik-letsencrypt-docker-compose.yml -p homepage ps
curl -s "https://${HOMEPAGE_HOSTNAME}/api/healthcheck"     # up
curl -s "https://${HOMEPAGE_HOSTNAME}/api/services" | jq '.[0].name'   # "Infrastructure"
```

`ps` shows `homepage`, `dockerproxy` and `traefik` running, `backups` running with no health check of its own, and `init-config` exited 0.

### Common first-deploy issues

- **`host validation failed`, or a bare 400 from a container that is healthy.** This is the one almost everybody hits, and the confusing part is the *healthy*: the container's own probe talks to `127.0.0.1:3000` and never sends a `Host` header, so it stays green while every real request is refused. `HOMEPAGE_ALLOWED_HOSTS` is compared against the Host header, which carries the port whenever the port is not the scheme's default — so on 443 the hostname alone is right, and behind anything on another port you must include it.
- **The dashboard is empty.** A YAML error in `config/services.yaml`. `curl -s https://<host>/api/services` shows what Homepage actually parsed.
- **Widgets show no container status.** `server:` in `services.yaml` must name an entry in `config/docker.yaml`, and the container must be one this stack's proxy can see.
- **Cert issuance fails.** DNS has not propagated, or port 80 is not reachable from the internet.
- **Networks not found.** Step 2 was skipped.

## Homepage never gets the Docker socket

Most Homepage compose files mount `/var/run/docker.sock` straight into the container. This one does not, and there are two reasons — the second is the one that will bite you.

The obvious one: a container with the Docker socket has, unless restricted, root on the host, and `:ro` on the mount is cosmetic, because the privilege is in what the API can do rather than in who can write the socket file.

The practical one: a direct socket mount **and** `no-new-privileges: true` fails with `connect EACCES`. The hardening blocks the supplementary-group access Homepage would need to open the socket file. The advice you will find in forums is to drop the hardening. This template keeps it and hands Homepage a proxy instead.

The proxy holds the socket and forwards exactly the container endpoints, with `POST` denied — so a widget can tell you something is unhealthy and can never act on it. Asserted on every CI run, along with the Homepage container's mount list, because the cheapest way for this to disappear is somebody adding the socket back for an afternoon:

| through the proxy | answer |
| :--- | :--- |
| `GET /containers/json` | `200` |
| `POST /containers/<id>/restart` | `403` |

There is no override file that turns `POST` on. A dashboard has no business writing to the Docker API.

## Put it behind something if it faces the internet

Homepage has no authentication of its own, by design — it is a page of links. That page describes your entire estate: what you run, where it lives, and often what version it is. If this hostname is reachable from outside your network, put an identity-aware proxy in front of it — Cloudflare Access, Authelia, a VPN. The Traefik dashboard in this stack is behind basic auth; Homepage deliberately is not, because half-measures on a page like this invite the assumption that it is protected.

## Updating

`./update.sh` moves this checkout to the latest release tag — a combination this repository's CI has booted and proven — and then runs `docker compose up -d`. It refuses to cross a major version unattended, refuses to run over local changes, and names any variable that became required since your version before anything has moved. `./update.sh --dry-run` says what would happen.

Your config directory is gitignored, so it is never a "local change" and never blocks an update.

## Supply chain trust

Four images pinned to `tag@sha256:<digest>` as interpolation defaults in the compose `x-images` block:

- [`ghcr.io/gethomepage/homepage`](https://github.com/gethomepage/homepage/pkgs/container/homepage): the dashboard, latest stable (v2.3.0)
- [`ghcr.io/tecnativa/docker-socket-proxy`](https://github.com/Tecnativa/docker-socket-proxy): the only container that touches the socket
- [`traefik`](https://hub.docker.com/_/traefik): reverse proxy
- [`alpine`](https://hub.docker.com/_/alpine): the seeding container and the backups sidecar

`git pull` alone delivers the tested combination; an `*_IMAGE_TAG` variable in `.env` overrides deliberately.

Two override levels exist per image. `<PREFIX>_IMAGE_VERSION` in `.env` swaps only the version of that image (Compose then pulls the tag, without a digest) and leaves every other pin as tested; `<PREFIX>_IMAGE_TAG` replaces the whole reference, digest included. Nested defaults need Docker Compose v2.5 or newer (2022).

The daily `check-pin-freshness` CI job re-resolves each pin against its registry and compares the pinned Homepage and Traefik versions against the latest upstream releases. Homepage's container tags carry the leading `v` (`v2.3.0`). GitHub Actions are pinned by commit SHA; Dependabot keeps those fresh.

## Production checklist

- [ ] **Decide what goes in front of it.** Homepage has no login; the page describes your estate.
- [ ] **Regenerate the Traefik dashboard hash.** The one in `.env.example` is a placeholder.
- [ ] **Replace the example services.** `config/services.yaml` ships two worked examples pointing at `example.com`.
- [ ] **Host-mount the backup volume.** By default the archives land in a named volume: if the host dies, they die with it.
- [ ] **Set `HOMEPAGE_ALLOWED_HOSTS` explicitly** if anything in front of Homepage serves on a port other than 443.

## Backups and restore

The `backups` container archives the config directory on a loop — a 30-minute warm-up, a 24-hour interval, 7-day retention, all overridable in `.env`. That directory is the entire application state: Homepage has no database, and everything it knows is the YAML you wrote.

Each archive is written to a `.partial` name, **read back with `tar -tzf`**, and only then renamed. The read-back is not decoration: BusyBox tar, which is what an alpine image ships, returns exit code 1 both for "a file changed while I was reading it" and for "I could not write the output at all", and an archive truncated after tar exited still carries exit status 0. Trusting the exit code alone renames an unreadable file into place and calls it a backup.

Restore with the interactive script:

```bash
chmod +x ./*.sh
./homepage-restore-config.sh
```

## Resource limits

Every service carries memory and CPU limits plus reservations as compose-level defaults: the same values CI boots the stack under. What moves these numbers is the number of widgets polling backends, not the number of links on the page. Override any of them in `.env` and the override survives every `git pull`. If a service is OOM-killed, `docker inspect <container> --format '{{.State.OOMKilled}}'` says so.

## Container hardening

Every service runs with `security_opt: no-new-privileges:true`. Homepage, the seeding container and the backups sidecar run with `cap_drop: [ALL]`; Traefik adds back `NET_BIND_SERVICE` and the sidecar the three it needs to write archives it owns. Homepage adds back nothing — and that is only possible because it does not have the Docker socket, which is the point made above.

## Testing

The [Deployment Verification](https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml?query=branch%3Amain) workflow runs on every push, pull request, and every day at 06:00 UTC: shellcheck and actionlint, Trivy scans of all four pinned images, the daily freshness check, and a deploy job that requires Homepage to answer **through Traefik** — not on its own loopback, which is what hides a broken host allow-list — the shipped configuration to parse into the services, bookmarks and widgets it defines, the seeding container to leave an edited file and a file of your own untouched on a second run, the Homepage container to have no Docker socket among its mounts, the proxy to answer `403` to a POST and `200` to a GET, an archive to be produced and to carry `services.yaml` and `settings.yaml` by name, eight backup and restore scenarios to pass, and Homepage to come back on the config directory the restore test replaced underneath it.

```bash
chmod +x tests/e2e-backup-restore.sh
./tests/e2e-backup-restore.sh
```

Run it on a staging copy, not on production: it stops the application and empties the config directory.

## Security notes

- Credentials are read from `.env` at deploy time; `.env` is gitignored and compose fails fast on missing required variables.
- The Docker socket is held by a proxy that denies every write, and Homepage does not have it.
- Homepage has no authentication of its own; put an identity-aware proxy in front if it faces the internet.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
