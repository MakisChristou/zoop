---
id: data-privacy
slug: /data-privacy
title: Data and privacy
description: Where your recordings live and what happens when you share them.
---

# Data and privacy

Zoop runs on a server you choose. There is no central Zoop account or hosted
health-data service required to use it.

## Who handles your data

The operator of the server you choose stores and manages your account and health
records. The Zoop project does not receive them merely because you installed the
app. A server administrator with database or host access can read stored records,
even though the app keeps users’ accounts separate.

Zoop has no advertising or tracking SDK. It does not sell health data. Your operator
controls their hosting, access logs, backups and any additional services they run.
Ask that operator about their privacy practices before connecting.

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

## Photos and permissions

Choosing a profile photo uploads that selected image to your server. Zoop does not
upload your photo library. Bluetooth access connects to the band. Notifications
are optional and can be disabled in iOS Settings.

## Retention and deletion

Recordings remain on the chosen server until you delete them through an available
account-deletion flow or ask its operator to erase them. This long-term history
supports reanalysis; signing out does not delete it.

On servers supporting account deletion, use Profile & settings → Account → Delete
account on iPhone and confirm your password. This permanently removes the account,
its assigned devices’ raw recordings and derived health history, profile photos,
goals and shared links. Active sessions and phone tokens are revoked. The last
enabled administrator must assign another administrator before deleting itself.
If an older server does not offer deletion, contact its operator or upgrade it.

The phone removes identified local queues and cached data for the deleted account.
Older queued frames with no recorded device identity cannot be safely assigned to
an account; remove the app to erase its entire local container. Copies already
exported to Apple Health, downloaded files or other people are not removed by
account deletion. Manage Apple Health records in the Health app.

Server backups can retain deleted records until the operator’s retention period
expires. Ask the operator about backup expiry and ensure a restored backup does not
republish deleted accounts or shared links.

The app marks its health-data storage and preferences for exclusion from device
backup. Unsynced recordings and development-only ECG files therefore need the
phone; losing it can lose records that have not reached your server. Existing
backups are not retroactively erased. Explicit exports are stored wherever you
choose to save them.

## Access, exports and questions

You can view your records in the app and web dashboard, export weights as CSV and
request a complete copy from your server operator. Operators can back up the full
PostgreSQL database. Only share health data deliberately.

For app issues, use [GitHub Issues](https://github.com/MakisChristou/zoop/issues).
Do not post passwords or health records publicly. Report security vulnerabilities
through [private vulnerability reporting](https://github.com/MakisChristou/zoop/security/advisories/new).
Requests concerning your account or server data should go to your server operator.

## The public website

This website and its documentation are separate from your Zoop installation.
Its product screenshots use synthetic sample data. Documentation search runs
locally in your browser; the site does not include analytics or load remote fonts.

Hosting providers may still keep access logs. This policy describes Zoop’s own behavior; it does not replace your server operator’s
privacy notice or describe a third party’s hosting practices.
