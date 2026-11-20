---
id: data-privacy
slug: /data-privacy
title: Data and privacy
description: Where your recordings live and what happens when you share them.
---

# Data and privacy

Zoop runs on a server you choose. There is no central Zoop account or hosted
health-data service required to use it.

## Where recordings live

Your band sends recordings to the iPhone over Bluetooth. The phone queues them
locally, uploads them to your server and removes acknowledged queue entries.
PostgreSQL stores the original recordings, derived measurements, accounts and
profile photos.

The dashboard reads from that server. Keep [backups](SELF_HOSTING.md#back-up-and-restore)
somewhere separate from the machine running it.

## Accounts and server access

Each account can access its assigned bands and health records. Administrator
statistics show operations without giving the administrator account access to
other users’ health records through the application.

Someone with access to the server or its database can read the stored data.
Choose a server operator you trust and protect its backups and credentials.

## Sharing

Sharing is optional. Choose the charts and time range to include, then create a
link with optional password protection and expiry. You can revoke it later.

Anyone who receives a working link and any required password can view its data.
Revoking a link stops future access; it cannot remove copies someone has already
saved. A one-year heatmap shares a longer period than a 30-day dashboard.

## Apple Health

The iPhone asks for permission before accessing Apple Health. Import and export
settings control which supported measurements it exchanges. Imported weight
readings become part of your Zoop history on your server.

## The public website

This website and its documentation are separate from your Zoop installation.
Its product screenshots use synthetic sample data. Documentation search runs
locally in your browser; the site does not include analytics or load remote fonts.

Hosting providers may still keep access logs. This page explains Zoop’s data
flow; it does not describe a third party’s hosting or privacy practices.
