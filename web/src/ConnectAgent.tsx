import { ProviderLogo, type Provider } from "./ProviderLogo";
import { useEffect, useRef, useState } from "react";
import { X, ExternalLink } from "lucide-react";
import { CopyValue, request } from "./AgentConnections";
import { LoadingBar } from "./Loading";

export function ConnectAgent({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [provider, setProvider] = useState<Provider>("Claude");
  const [url, setUrl] = useState("");
  const [error, setError] = useState("");
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const focused = document.activeElement as HTMLElement | null;
    const el = dialog.current;
    el?.showModal();
    return () => {
      el?.close();
      focused?.focus();
    };
  }, []);
  useEffect(() => {
    const c = new AbortController();
    setError("");
    request<{ mcp_url: string }>(
      "/v1/agent-connections",
      undefined,
      c.signal,
      "GET",
    )
      .then((d) => {
        if (!c.signal.aborted) setUrl(d.mcp_url);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e.message);
      });
    return () => c.abort();
  }, [attempt]);
  const destination =
    provider === "Claude"
      ? "https://claude.ai/settings/connectors"
      : "https://chatgpt.com/#settings/Connectors";
  return (
    <dialog
      ref={dialog}
      className="goal-dialog connect-agent-dialog"
      aria-labelledby="connect-title"
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
    >
      <header>
        <h2 id="connect-title">Connect your agent</h2>
        <button aria-label="Close" onClick={onClose}>
          <X size={18} />
        </button>
      </header>
      <div
        className="provider-picker"
        role="group"
        aria-label="Choose your agent"
      >
        {(["Claude", "ChatGPT", "Other"] as const).map((p) => (
          <button
            key={p}
            aria-label={p}
            title={p}
            aria-pressed={provider === p}
            onClick={() => setProvider(p)}
          >
            <ProviderLogo provider={p} />
          </button>
        ))}
      </div>
      {error ? (
        <p className="error" role="alert">
          {error}{" "}
          <button onClick={() => setAttempt((n) => n + 1)}>Retry</button>
        </p>
      ) : !url ? (
        <LoadingBar label="Loading server URL" />
      ) : (
        <label className="agent-server-label">
          Server URL
          <CopyValue value={url} label="Copy server URL" />
        </label>
      )}
      <ol className="connect-steps">
        <li>
          {provider === "Other"
            ? "Open your agent’s MCP settings."
            : `Open ${provider}’s connector settings.`}
        </li>
        <li>Add a custom connector with this URL.</li>
        <li>Sign in to Zoop and choose what to share.</li>
      </ol>
      <p className="connect-privacy">
        Read-only. You choose the data and can disconnect anytime.
      </p>
      <footer>
        {provider === "Other" ? (
          <a href="#Settings/agents" onClick={onClose}>
            Manage access keys
          </a>
        ) : (
          <a
            className="primary connect-open"
            href={destination}
            target="_blank"
            rel="noopener noreferrer"
          >
            Open {provider}
            <ExternalLink size={15} />
          </a>
        )}
      </footer>
    </dialog>
  );
}
