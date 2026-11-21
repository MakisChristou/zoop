---
id: self-hosting
slug: /self-hosting
title: Run your own Zoop
description: Install, back up and update your Zoop server with Docker Compose.
---

# Run your own Zoop

Docker Compose runs the dashboard, API and PostgreSQL. The iPhone app collects
recordings from your band; both clients use the same server-owned metrics.

You need Docker Engine with Compose v2, Git, and enough disk for your recordings.
The first build compiles Rust and the web app. Prebuilt release images are not
published yet. Linux amd64 is tested; Apple Silicon/arm64 validation is still pending.

## Start

```sh
git clone https://github.com/MakisChristou/zoop.git
cd zoop
./tools/setup.sh
docker compose up -d --build --wait
./tools/setup.sh --show-code
```

Open **http://localhost:8080**, enter the setup code, and create your admin account.
Keep `.env` private: it contains generated database credentials and the setup code.
Setup closes after the first account is created. Restarting does not reopen it.

The default port listens only on this machine. To connect a phone over your LAN,
choose the server's LAN address when generating the configuration instead:

```sh
ZOOP_BIND=192.168.1.20 ./tools/setup.sh http://192.168.1.20:8080
```

Replace the example address with yours. If `.env` already exists, edit its
`ZOOP_ORIGIN` and `ZOOP_BIND` instead; the setup command never overwrites it.
`ZOOP_PORT` changes the host port. Reapply changes with `docker compose up -d --wait`.

## Access and HTTP

Zoop serves HTTP. You choose the network arrangement: local access, a VPN, or your
own HTTPS reverse proxy. It does not manage DNS, certificates or router settings.

`ZOOP_ORIGIN` must be the exact URL users open, including any non-default port,
without a path or trailing slash. Proxy the whole origin to the web container;
it serves the dashboard and forwards API requests. Do not expose PostgreSQL or
the API container separately. A proxy on another host or Docker network needs an
explicit reachable `ZOOP_BIND`; the default loopback listener is host-local.

Browser sessions use HttpOnly, SameSite cookies and origin checks. HTTPS origins
also use Secure cookies. HTTP carries passwords and health data unencrypted:
use it only on a trusted network or through a VPN. HTTPS retains normal certificate
validation; Zoop does not accept arbitrary self-signed certificates. Some browsers
require HTTPS for clipboard access; on HTTP, open a shared link and copy its address.

## Connect your iPhone

Open Zoop on your iPhone and enter the same server address and account credentials.
See the [iPhone guide](IPHONE_SETUP.md) for app availability and connection steps.
Allow local-network access if iOS asks. The app supports HTTP and HTTPS self-hosted
addresses.

Each band must belong to an account before uploads are accepted. You can enter its
serial during setup or assign it later from the server:

```sh
docker compose exec api /usr/local/bin/zoop --config /etc/zoop/zoop.toml \
  account bind-device --email owner@example.com --device YOUR_STRAP_SERIAL
```

Use the strap serial, not its Bluetooth UUID. Ownership is explicit; the server
never gives an account somebody else's recordings automatically.

## More accounts and password recovery

There is no public sign-up. Create additional accounts with the operator command.
Put the password in a local file readable only by you (`chmod 600`), then pass it
through standard input:

```sh
docker compose exec -T api /usr/local/bin/zoop --config /etc/zoop/zoop.toml \
  account create --email member@example.com --password-file - < /secure/path/password.txt
```

Use `account reset-password` with the same arguments to recover an account. This
revokes its existing sessions and phone tokens. Add `--admin` only when creating
an administrator. Admin statistics do not grant access to other users' health data.
Emails are login identifiers; Zoop does not send email or require an SMTP server.

## Back up and restore

PostgreSQL stores accounts, original recordings, derived metrics and profile photos
in the `database` Docker volume. `docker compose down` preserves it; **`down -v`
deletes it**. Keep an encrypted copy of `.env` alongside your backups.

```sh
mkdir -p backups
./tools/backup.sh backups/zoop.dump
```

The dump is a consistent database snapshot, created with private permissions.
The command refuses to overwrite a file. Choose a new filename for each backup;
copy backups off the server and periodically test restoration.

Restore into a **new installation**, before starting its API:

```sh
./tools/setup.sh
docker compose up -d --wait database
./tools/restore.sh /path/to/zoop.dump
docker compose up -d --build --wait
```

Restore refuses a database containing tables. Existing accounts, ownership and
recordings return with the dump; first-run setup remains closed. Apply your chosen
origin and bind address to the new installation's `.env` before starting it.

## Update and troubleshoot

Back up first, check release notes, then check out the desired revision and run:

```sh
docker compose up -d --build --wait
docker compose ps
docker compose logs --tail 100 api web
```

Pending migrations run before the API starts. An application downgrade may be
incompatible with a newer database: restore the matching backup into a separate
installation instead of forcing an old binary onto it.

`/health` reports API liveness; `/ready` also checks worker readiness. A failed
migration or health check prevents the stack from being reported ready. Logs can
include device identifiers; redact them before sharing. If setup is unavailable on
an existing database, use the operator commands rather than deleting accounts.
