---
id: connect-agent
slug: /connect-agent
title: Connect your agent
description: Let your own assistant read selected Zoop data.
---

# Connect your agent

Use your preferred assistant to ask about your sleep, activity, recovery, weight
or goals. Zoop supplies the measurements. You choose the model and where it runs.
This connection cannot edit your health records or manage your account.

## Connect

1. Select **Connect your agent** at the top of your dashboard and choose your agent’s logo.
2. Copy the **Server URL** into your agent’s remote MCP settings.
3. Sign in to your own Zoop server when prompted. Choose the data categories,
   history window and expiry, then select **Allow read access**.

The default history window is the last 30 days; 90 days and all history are also
available. New readings enter the window until the connection expires. Each
connection is tied to the band selected when you approve it.

Your agent may send readings to its model provider. Check that provider’s retention
and privacy settings. Revoking access stops future requests; it cannot erase copies
already received. Never connect a shared team credential to your private readings.

### Access keys

If your client supports a fixed authorization header instead of sign-in, open
**Settings → Connected apps → Access keys**. Choose its permissions and create a key. Save it immediately
in your agent’s secret settings; Zoop only shows it once.

Use the HTTP header `Authorization: Bearer <your access key>`. Do not put keys in
URLs, chat prompts, shared configuration files or source control. Phone credentials
and public dashboard links cannot be used as agent keys.

### Network access

A local agent can reach Zoop over your LAN or VPN. A cloud-hosted connector must
reach your server from the provider’s infrastructure; access from your laptop alone
is not enough. Claude and ChatGPT need a publicly reachable HTTPS endpoint on port 443.

Zoop does not expose your server automatically or bundle a TLS proxy. Choose your
own access arrangement. Use encrypted transport outside a trusted local connection.
The regular Docker web service forwards MCP and OAuth to the API. If using your own
reverse proxy, also forward `/mcp`, `/oauth/` and `/.well-known/oauth-` paths, preserving
the original Host header. Set `ZOOP_ORIGIN` to the exact external dashboard origin.

## Ask a question

- “Compare my sleep and recovery over the last month.”
- “How is my weight progressing during this goal?”
- “Summarize my workouts last week.”

The agent can request at most 90 days at a time and can page through longer permitted
history. Dates use the timezone you selected at consent. Missing or pending readings
stay missing. Connections return the same backend measurements used by the apps;
the assistant’s conclusions are its own and are not a medical diagnosis.

**Sleep** covers sessions, timing and stages. **Recovery** also includes nightly HRV
and resting heart rate. **Activity** includes workouts, steps, load and workout heart
rate. **Goals** includes planned targets; measured progress also requires **Weight**.
Raw recordings, profile pictures, device identifiers and administrative data are not
exposed.

## Revoke access

Open **Settings → Connected apps** and select **Disconnect**. The connection stops working on its
next request, including existing OAuth refresh tokens. Password recovery, account
disabling/deletion and band ownership changes also invalidate connections.

## Scripts and other clients

The same permissions protect the JSON read API. Its machine-readable specification
is available at `/v1/agent-openapi.json` on your server.

With `ZOOP_URL` and `ZOOP_AGENT_KEY` supplied through your local secret management:

```sh
curl --fail --silent --show-error \
  -H "Authorization: Bearer $ZOOP_AGENT_KEY" \
  "$ZOOP_URL/v1/agent/daily_summary"
```

Read endpoints: `available_data`, `daily_summary`, `sleep_history`,
`recovery_history`, `activity_history`, `weight_history`, `goals` and
`metric_definitions`. Optional `from` and `to` parameters are inclusive local dates
in `YYYY-MM-DD` format. Account, device and timezone cannot be overridden by a call.

MCP uses Streamable HTTP. OAuth clients must support authorization code with S256
PKCE and resource indicators. Client ID Metadata Documents are preferred, with
dynamic public-client registration as a fallback. No client secret or API key is
needed for OAuth. Connector availability depends on your provider’s plan and
workspace settings.

In Claude, open **Settings → Connectors → Add custom connector**. In ChatGPT, enable
developer mode where available, then add an app in its Apps/Connectors settings.
Paste Zoop’s Server URL exactly, including `/mcp`, and use OAuth. The provider opens
your Zoop sign-in and permission screen. Your Zoop password stays with your server.
