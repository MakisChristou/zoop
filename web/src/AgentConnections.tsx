import { CopyValue } from "./CopyValue";
import { ConnectAgent } from "./ConnectAgent";
import { ProviderLogo } from "./ProviderLogo";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { ChevronDown, LoaderCircle } from "lucide-react";
import { sharingRequest } from "./sharing";
import { LoadingBar } from "./Loading";

const permissions = [
  ["sleep:read", "Sleep", "Timing and stages"],
  ["recovery:read", "Recovery", "Score, HRV and resting heart rate"],
  ["activity:read", "Activity", "Workouts, heart rate, steps and load"],
  ["weight:read", "Weight", "Measurements and sources"],
  ["goals:read", "Goals", "Plans; progress also needs Weight"],
] as const;
type Connection = {
  id: number;
  name: string;
  scopes: string[];
  history_days: number | null;
  expires_at: string;
  revoked_at: string | null;
  last_used_at: string | null;
  client_id: string | null;
};
type List = { connections: Connection[]; mcp_url: string; api_url: string };
type Consent = {
  device_id: string;
  name: string;
  scopes: string[];
  history_days: number | null;
  timezone: string;
  expires_in_days: number;
};
export async function request<T>(
  path: string,
  body?: unknown,
  signal?: AbortSignal,
  method = "POST",
): Promise<T> {
  try {
    return await sharingRequest<T>(path, body, signal, method);
  } catch (error) {
    if (!signal?.aborted && (error as { status?: number }).status === 401)
      window.dispatchEvent(new Event("zoop:unauthorized"));
    throw error;
  }
}
const date = (value: string) =>
  new Date(value).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric",
  });

type Devices = { device?: string; devices: string[] };

export function AgentConnections({ device, devices }: Devices) {
  const [data, setData] = useState<List | null>(null),
    [busy, setBusy] = useState(true),
    [error, setError] = useState(""),
    [attempt, setAttempt] = useState(0);
  const [adding, setAdding] = useState(false),
    [key, setKey] = useState("");
  const [revoking, setRevoking] = useState<number | null>(null);
  const lifetime = useRef(new AbortController());
  useEffect(() => {
    lifetime.current = new AbortController();
    return () => lifetime.current.abort();
  }, []);
  useEffect(() => {
    const c = new AbortController();
    setBusy(true);
    setError("");
    request<List>("/v1/agent-connections", undefined, c.signal, "GET")
      .then((v) => {
        if (!c.signal.aborted) setData(v);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e.message);
      })
      .finally(() => {
        if (!c.signal.aborted) setBusy(false);
      });
    return () => c.abort();
  }, [attempt]);
  useEffect(() => {
    const refresh = () => setAttempt((n) => n + 1);
    window.addEventListener("focus", refresh);
    return () => window.removeEventListener("focus", refresh);
  }, []);
  async function revoke(id: number) {
    setRevoking(id);
    setError("");
    try {
      await request(
        `/v1/agent-connections/${id}`,
        undefined,
        lifetime.current.signal,
        "DELETE",
      );
      if (!lifetime.current.signal.aborted) setAttempt((n) => n + 1);
    } catch (e) {
      if (!lifetime.current.signal.aborted) setError((e as Error).message);
    } finally {
      if (!lifetime.current.signal.aborted) setRevoking(null);
    }
  }
  return (
    <section className="agent-page">
      <h1>Connected apps</h1>
      {busy && <LoadingBar label="Loading connections" />}
      {error && (
        <p role="alert" className="error">
          {error}{" "}
          <button onClick={() => setAttempt((n) => n + 1)}>Retry</button>
        </p>
      )}
      {data && <ConnectAgent url={data.mcp_url} />}
      {data && data.connections.length > 0 && (
        <>
          <h2 className="connections-title">Your connections</h2>
          <div className="connection-list">
            {data.connections.map((c) => {
              const status = c.revoked_at
                ? "Disconnected"
                : Date.parse(c.expires_at) <= Date.now()
                  ? "Expired"
                  : "Active";
              const provider =
                c.client_id === "https://chatgpt.com/oauth/client.json"
                  ? "ChatGPT"
                  : c.client_id ===
                      "https://claude.ai/oauth/mcp-oauth-client-metadata"
                    ? "Claude"
                    : "Other";
              return (
                <details key={c.id} className="agent-row">
                  <summary aria-label={`Details for ${c.name}`}>
                    <span className="connection-icon">
                      <ProviderLogo provider={provider} />
                    </span>
                    <span className="connection-info">
                      <strong>{c.name}</strong>
                      <small>
                        {c.scopes
                          .map(
                            (s) =>
                              permissions.find((p) => p[0] === s)?.[1] ?? s,
                          )
                          .join(", ")}{" "}
                        ·{" "}
                        {c.history_days
                          ? `Last ${c.history_days} days`
                          : "All history"}
                      </small>
                    </span>
                    <span className="connection-status">
                      {status === "Active" && <i />}
                      {status}
                    </span>
                    <ChevronDown className="connection-chevron" size={15} />
                  </summary>
                  <div className="connection-details">
                    <p>
                      Expires {date(c.expires_at)} ·{" "}
                      {c.last_used_at
                        ? `Last used ${date(c.last_used_at)}`
                        : "Not used yet"}
                    </p>
                    {status === "Active" && (
                      <button
                        disabled={revoking !== null}
                        onClick={() => revoke(c.id)}
                      >
                        {revoking === c.id && (
                          <LoaderCircle className="spinner" size={16} />
                        )}
                        Disconnect
                      </button>
                    )}
                  </div>
                </details>
              );
            })}
          </div>
        </>
      )}
      {data && device && (
        <details
          className="agent-advanced"
          open={adding}
          onToggle={(e) => {
            setAdding(e.currentTarget.open);
            if (!e.currentTarget.open) setKey("");
          }}
        >
          <summary>
            Access keys <span>Advanced</span>
          </summary>
          <section className="panel agent-connect">
            {key ? (
              <div role="status">
                <p>Save this key now. It won’t be shown again.</p>
                <CopyValue value={key} label="Copy access key" secret />
                <p>
                  Keep it in your agent’s secret settings, never in a chat or
                  repository.
                </p>
                <button
                  onClick={() => {
                    setAdding(false);
                    setKey("");
                  }}
                >
                  Done
                </button>
              </div>
            ) : (
              <ConsentForm
                device={device}
                devices={devices}
                button="Create access key"
                onSave={async (consent, signal) => {
                  const result = await request<{ key: string }>(
                    "/v1/agent-connections",
                    consent,
                    signal,
                  );
                  if (!signal.aborted) {
                    setKey(result.key);
                    setAttempt((n) => n + 1);
                  }
                }}
              />
            )}
          </section>
        </details>
      )}
    </section>
  );
}
function ConsentForm({
  device,
  devices,
  allowed = permissions.map((p) => p[0]),
  button,
  onSave,
  name = "",
  showName = true,
}: {
  device: string;
  devices: string[];
  allowed?: readonly string[];
  button: string;
  name?: string;
  showName?: boolean;
  onSave: (value: Consent, signal: AbortSignal) => Promise<void>;
}) {
  const [consent, setConsent] = useState<Consent>({
    device_id: device,
    name,
    scopes: [],
    history_days: 30,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
    expires_in_days: 90,
  });
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const controller = useRef(new AbortController());
  useEffect(() => {
    controller.current = new AbortController();
    return () => controller.current.abort();
  }, []);
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await onSave(consent, controller.current.signal);
    } catch (e) {
      if (!controller.current.signal.aborted) setError((e as Error).message);
    } finally {
      if (!controller.current.signal.aborted) setBusy(false);
    }
  }
  return (
    <form className="agent-form" onSubmit={submit}>
      {showName && (
        <label>
          Name
          <input
            required
            maxLength={80}
            value={consent.name}
            onChange={(e) => setConsent({ ...consent, name: e.target.value })}
            placeholder="My assistant"
          />
        </label>
      )}
      {devices.length > 1 && (
        <label>
          Band
          <select
            value={consent.device_id}
            disabled={busy}
            onChange={(e) =>
              setConsent({ ...consent, device_id: e.target.value })
            }
          >
            {devices.map((id) => (
              <option key={id} value={id}>
                {id}
              </option>
            ))}
          </select>
        </label>
      )}
      <fieldset disabled={busy}>
        <legend>Read access</legend>
        {permissions
          .filter(([scope]) => allowed.includes(scope))
          .map(([scope, label, detail]) => (
            <label className="agent-permission" key={scope}>
              <input
                type="checkbox"
                checked={consent.scopes.includes(scope)}
                onChange={(e) =>
                  setConsent({
                    ...consent,
                    scopes: e.target.checked
                      ? [...consent.scopes, scope]
                      : consent.scopes.filter((s) => s !== scope),
                  })
                }
              />
              <span>
                {label}
                <small>{detail}</small>
              </span>
            </label>
          ))}
      </fieldset>
      <div className="agent-options">
        <label>
          History
          <select
            value={consent.history_days ?? "all"}
            onChange={(e) =>
              setConsent({
                ...consent,
                history_days:
                  e.target.value === "all" ? null : Number(e.target.value),
              })
            }
          >
            <option value="30">Last 30 days</option>
            <option value="90">Last 90 days</option>
            <option value="all">All history</option>
          </select>
        </label>
        <label>
          Expires in
          <select
            value={consent.expires_in_days}
            onChange={(e) =>
              setConsent({
                ...consent,
                expires_in_days: Number(e.target.value),
              })
            }
          >
            <option value="7">7 days</option>
            <option value="30">30 days</option>
            <option value="90">90 days</option>
            <option value="365">1 year</option>
          </select>
        </label>
      </div>
      <label>
        Time zone
        <input
          required
          value={consent.timezone}
          onChange={(e) => setConsent({ ...consent, timezone: e.target.value })}
        />
      </label>
      <p>
        Includes new readings until expiry. Your agent may send these readings
        to its model provider. Revoking access won’t erase copies already
        received.
      </p>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <button
        className="primary"
        disabled={busy || consent.scopes.length === 0}
      >
        {busy && <LoaderCircle size={16} className="spinner" />}
        {button}
      </button>
    </form>
  );
}
export function AgentAuthorization({ device, devices }: Devices) {
  const [details, setDetails] = useState<{
      client_name: string;
      client_id?: string;
      redirect_uri: string;
      scopes: string[];
    } | null>(null),
    [error, setError] = useState("");
  const [attempt, setAttempt] = useState(0);
  const [cancelling, setCancelling] = useState(false);
  const consentLifetime = useRef(new AbortController());
  useEffect(() => {
    consentLifetime.current = new AbortController();
    return () => consentLifetime.current.abort();
  }, []);
  const query = location.hash.split("?")[1] || "";
  useEffect(() => {
    const c = new AbortController();
    setDetails(null);
    setError("");
    request<typeof details>(
      `/v1/agent-authorization?${query}`,
      undefined,
      c.signal,
      "GET",
    )
      .then((d) => {
        if (!c.signal.aborted) setDetails(d);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e.message);
      });
    return () => c.abort();
  }, [query, attempt]);
  return (
    <section className="agent-page">
      <h1>Connect your agent</h1>
      {error ? (
        <p role="alert" className="error">
          {error}{" "}
          <button onClick={() => setAttempt((n) => n + 1)}>Retry</button>
        </p>
      ) : !details ? (
        <LoadingBar label="Checking agent" />
      ) : (
        <section className="panel">
          <h2>{details.client_name}</h2>
          {details.client_id?.startsWith("https://") && (
            <p>{new URL(details.client_id).hostname}</p>
          )}
          <p className="agent-callback">
            Returns to {new URL(details.redirect_uri).origin}
          </p>
          {device ? (
            <ConsentForm
              key={query + device}
              device={device}
              devices={devices}
              name={details.client_name}
              showName={false}
              allowed={details.scopes}
              button="Allow read access"
              onSave={async (consent, signal) => {
                const result = await request<{ redirect_to: string }>(
                  "/v1/agent-authorization",
                  {
                    authorization: Object.fromEntries(
                      new URLSearchParams(query),
                    ),
                    consent,
                  },
                  signal,
                );
                if (!signal.aborted) location.assign(result.redirect_to);
              }}
            />
          ) : (
            <p>Link a band before connecting an agent.</p>
          )}
          <button
            className="agent-cancel"
            disabled={cancelling}
            onClick={async () => {
              setCancelling(true);
              try {
                const result = await request<{ redirect_to: string }>(
                  "/v1/agent-authorization/deny",
                  Object.fromEntries(new URLSearchParams(query)),
                  consentLifetime.current.signal,
                );
                if (!consentLifetime.current.signal.aborted)
                  location.assign(result.redirect_to);
              } catch (e) {
                setError((e as Error).message);
                setCancelling(false);
              }
            }}
          >
            {cancelling && <LoaderCircle size={16} className="spinner" />}Cancel
          </button>
        </section>
      )}
    </section>
  );
}
