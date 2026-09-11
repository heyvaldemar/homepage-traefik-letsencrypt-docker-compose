# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-09-11

First release. A production deployment of Homepage behind Traefik, built to the
fleet standard established in
[keycloak-traefik-letsencrypt-docker-compose](https://github.com/heyvaldemar/keycloak-traefik-letsencrypt-docker-compose).

### Added

- **Homepage v2.3 behind Traefik with Let's Encrypt TLS.** Four images pinned by
  `tag@sha256:<digest>` in the compose `x-images` block: the dashboard, a
  Docker socket proxy, Traefik, and a plain alpine used by both the seeding
  container and the backups sidecar.
- **Homepage never gets the Docker socket**, and there are two reasons. The
  obvious one: a container holding it has root on the host unless restricted,
  and `:ro` on the mount is cosmetic. The practical one: a direct socket mount
  *and* `no-new-privileges: true` fails with `connect EACCES`, because the
  hardening blocks the supplementary-group access needed to open the socket
  file. The advice in circulation is to drop the hardening. This keeps it and
  hands Homepage a proxy that forwards only the container endpoints with `POST`
  denied. Asserted every run: `GET /containers/json` answers 200, `POST
  /containers/<id>/restart` answers 403, and the Homepage container has no
  socket among its mounts.
- **A configuration directory that git never owns.** Homepage is configured by
  hand-written YAML, so the starting point ships as `config.example/`, a
  seeding container copies it into an empty config directory once, and the
  directory is gitignored. Without that, every `git pull` would collide with
  your edits and `update.sh` — which refuses to run over local changes — would
  refuse to run at all. CI asserts both directions: an empty directory gets
  seeded, and a second run leaves an edited file byte-for-byte alone along with
  files `config.example` has never heard of.
- **A smoke test that goes through Traefik**, not through the container's own
  loopback. See the note on host validation below: the loopback check is
  exactly the one that cannot see the most common failure.
- **The shipped configuration is parsed and served back in CI.**
  `config.example/` is the first thing a new deployment sees, and a typo in it
  is a blank dashboard for everyone who clones this. The deploy job asks
  Homepage for the services, bookmarks and widgets it parsed and checks they
  are the ones the files define.
- **A backup loop that reads its own archive back before naming it a backup**,
  an end-to-end suite that requires `services.yaml` and `settings.yaml` in the
  archive by name, a restore script, `update.sh`, `cap_drop: ALL` on every
  service, resource limits and reservations, and OpenSSF Scorecard.

### Notes

- **`HOMEPAGE_ALLOWED_HOSTS` is required since v1.0, and its failure mode hides
  behind a green health check.** The value is compared against the Host
  *header*, which carries the port whenever the port is not the scheme's
  default — so on 443 the hostname alone is right, and behind anything on
  another port it is not. When it does not match, every request is answered
  with 400 while the container reports itself healthy, because its own probe
  talks to `127.0.0.1:3000` and never sends the header. Found on this
  template's first local boot, on port 8443.
- **Homepage's container tags carry the leading `v`** (`v2.3.0`). The freshness
  check compares the git tag as it comes rather than stripping it.
- **There is no Buffering middleware, deliberately.** Traefik streams bodies
  unless one is attached; attaching it is what turns buffering on, and `0` on
  its limits means *no size ceiling*, not *off*. Measured against a response
  that takes four seconds to produce: 0.03s to the first byte without it, 4.15s
  with it.

[Unreleased]: https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
