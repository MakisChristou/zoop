---
id: help
slug: /help
title: Troubleshooting
description: Fix common server, login and band connection problems.
---

# Troubleshooting

## The dashboard won’t open

From your Zoop directory, check:

```sh
docker compose ps
docker compose logs --tail 100 api web
```

The first source build can take time. If a service fails, read its first error.
Do not delete the database to resolve a startup problem.

## It works on the server, but not my iPhone

`localhost` on your iPhone means the phone itself. Use the server’s LAN address,
VPN address or configured hostname instead. Check that `ZOOP_ORIGIN` matches the
address you open and `ZOOP_BIND` is reachable from your phone.

Allow local-network access for Zoop in iOS Settings. Open the server address in
Safari first; if that fails too, check the network and firewall.

See [access and HTTP](SELF_HOSTING.md#access-and-http) for configuration details.

## I can’t sign in

Use an account created on this server. There is no public registration or email
password reset; the server operator can [reset your password](SELF_HOSTING.md#more-accounts-and-password-recovery).

If setup says an account already exists, that is expected after the first run.
Restarting does not reopen setup.

## My band connects, but data is missing

Check that its **strap serial**, not the Bluetooth UUID, belongs to your account.
See the [device ownership command](SELF_HOSTING.md#connect-your-iphone).

Keep the official WHOOP app closed while connecting through Zoop. Do not unpair
the band. Leave Zoop open briefly to check syncing; a disconnected phone keeps
recordings queued until the server is reachable again.

## Recovery is still empty

Recovery needs enough eligible sleep history. A partial night, pending analysis
or unusual signals can also prevent a score. See [Recovery requirements](METRICS_GUIDE.md#recovery).

## Report a problem

[Open an issue](https://github.com/MakisChristou/zoop/issues) with your Zoop revision,
phone/iOS or server version, what you expected and what happened.

Redact tokens, passwords, device identifiers and personal health data from logs
and screenshots. Never attach `.env` or a database dump.

For security issues, follow the [security policy](https://github.com/MakisChristou/zoop/blob/main/SECURITY.md).
