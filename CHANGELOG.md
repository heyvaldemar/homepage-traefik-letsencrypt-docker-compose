# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.4] - 2026-09-19

### Security

- **`alpine:3.22` was rebuilt upstream**; the pin moved from `sha256:365499d9dccb…` to `sha256:5291449c3df7…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.0.3] - 2026-09-18

### Security

- **`traefik:3.7` was rebuilt upstream**; the pin moved from `sha256:f86a2cab1b5c…` to `sha256:1c32e7c36820…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.
- **`alpine:3.22` was rebuilt upstream**; the pin moved from `sha256:14358309a308…` to `sha256:365499d9dccb…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.0.2] - 2026-09-17

### Changed

- **`ghcr.io/gethomepage/homepage:v2.3.0` moved to `ghcr.io/gethomepage/homepage:v2.4.0`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.

## [1.0.1] - 2026-09-11

### Fixed

- **The socket proxy is watched and scanned like every other pinned image.** It
  was added as a fourth image and then left out of both the daily freshness
  check and the Trivy matrix. A pin nobody watches goes stale in silence, and
  this is the one container in the stack holding the Docker socket — the last
  image that should be scanned by nobody.

  Found by the fleet conformance rule that asserts every digest-pinned image
  has a freshness job behind it. The gap was invisible from inside this
  repository, where every build was green.

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
- **Homepage needs `DAC_OVERRIDE`, and nothing else.** It writes a logs
  directory inside the config directory on every start; that directory belongs
  to whichever uid owns it on the host, and the container runs as root, which
  without that capability cannot create anything inside a directory it does not
  own. The symptom is the confusing kind: the server starts, passes its own
  health check, and answers 500 to every page with `EACCES: permission denied,
  mkdir '/app/config/logs'` in its log. Found by CI on a real host; Docker
  Desktop virtualises bind-mount ownership and never shows it.
- **The seeding container hands the files to the config directory's owner.**
  The first version used `cp -a` with every capability dropped, which worked on
  the maintainer's Docker Desktop — where bind-mount ownership is virtualised —
  and failed on a real host with `Permission denied` for every file. Two
  separate things were wrong: a root process without `DAC_OVERRIDE` cannot
  write into a directory owned by someone else, and `cp -a` tries to preserve
  ownership, which needs `CHOWN`. It now copies without preserving and then
  chowns everything to whatever uid owns the directory — because files you
  cannot edit without sudo, in a directory the README calls yours, are not much
  use.
- **Homepage's container tags carry the leading `v`** (`v2.3.0`). The freshness
  check compares the git tag as it comes rather than stripping it.
- **There is no Buffering middleware, deliberately.** Traefik streams bodies
  unless one is attached; attaching it is what turns buffering on, and `0` on
  its limits means *no size ceiling*, not *off*. Measured against a response
  that takes four seconds to produce: 0.03s to the first byte without it, 4.15s
  with it.

[Unreleased]: https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/releases/tag/v1.0.1
[1.0.0]: https://github.com/heyvaldemar/homepage-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
