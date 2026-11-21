---
id: get-started
slug: /get-started
title: Get started
description: Set up your own Zoop server and connect your iPhone.
---

# Get started

Zoop collects recordings from your WHOOP and keeps them on your server.
Your iPhone and web dashboard show the same sleep, recovery, activity and weight history.

## Before you start

You’ll need three things:

- **Band:** WHOOP 5.0 or MG.
- **Phone:** an iPhone running iOS 17 or later, with Zoop installed.
- **Server:** a machine running Docker with Compose v2.

The iPhone app is awaiting App Store approval. The download link will appear in
the [iPhone guide](IPHONE_SETUP.md#install-zoop) when it is available.

## 1. Start your server

```sh
git clone https://github.com/MakisChristou/zoop.git
cd zoop
./tools/setup.sh
docker compose up -d --build --wait
./tools/setup.sh --show-code
```

The commands above use Git to download the project. You can also download and
extract the [source ZIP](https://github.com/MakisChristou/zoop/archive/refs/heads/main.zip),
open its folder in Terminal, and start with `./tools/setup.sh`.

Docker builds the API and dashboard; you do not need Rust or Node installed.
Wait for Compose to report them healthy. Linux amd64 is tested; arm64 validation is pending.

Open **http://localhost:8080**, enter the setup code and create your admin account.
Keep the generated `.env` file private. Once an account exists, setup closes.

## 2. Make it reachable from your phone

The default address works only on the server itself. For a trusted home network,
set these values in `.env`, using your server’s actual LAN address:

```dotenv
ZOOP_ORIGIN=http://192.168.1.20:8080
ZOOP_BIND=192.168.1.20
```

Then apply the change:

```sh
docker compose up -d --wait
```

Open that address in Safari on your iPhone to check the connection. HTTP sends
passwords and health data unencrypted: use a trusted LAN or VPN, or configure your
own HTTPS proxy. See [network options](SELF_HOSTING.md#access-and-http).

## 3. Connect your band

[Open Zoop on your iPhone](IPHONE_SETUP.md), then sign in with your server
address and account. Assign your band’s serial to the account during server setup
or with the [device ownership command](SELF_HOSTING.md#connect-your-iphone).

Pair the band in the official WHOOP app first. Quit that app before connecting
with Zoop, and keep the existing Bluetooth bond.

## 4. Check your first recordings

Leave Zoop connected to your band while it syncs. Open the web dashboard with the
same account to see the uploaded data. Some measurements need a full night or
several nights of history; an empty Recovery ring is expected at first.

[Understand your measurements](METRICS_GUIDE.md), then set up your first
[backup](SELF_HOSTING.md#back-up-and-restore). If something is missing,
start with [troubleshooting](HELP.md).
