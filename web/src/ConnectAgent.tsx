import { useState } from "react";
import { ArrowUpRight, LockKeyhole } from "lucide-react";
import { ProviderLogo, type Provider } from "./ProviderLogo";
import { CopyValue } from "./CopyValue";

const providers = {
  ChatGPT: {
    url: "https://chatgpt.com/plugins",
    hint: (
      <>
        In <strong>Plugins</strong>, choose{" "}
        <strong>Add custom MCP server</strong>. Paste the URL and select OAuth.
      </>
    ),
  },
  Claude: {
    url: "https://claude.ai/settings/connectors",
    hint: (
      <>
        In <strong>Connectors</strong>, choose{" "}
        <strong>Add custom connector</strong> and paste the URL.
      </>
    ),
  },
  Other: {
    url: null,
    hint: (
      <>
        Add this URL to your client’s <strong>remote MCP servers</strong> and
        select OAuth.
      </>
    ),
  },
};
export function ConnectAgent({ url }: { url: string }) {
  const [provider, setProvider] = useState<Provider>("ChatGPT");
  const { url: destination, hint } = providers[provider];
  return (
    <section className="agent-setup" aria-labelledby="connect-title">
      <div className="setup-body">
        <div className="setup-head">
          <h2 id="connect-title">
            Set up {provider === "Other" ? "your client" : provider}
          </h2>
          <div
            className="provider-picker"
            role="group"
            aria-label="Choose your agent"
          >
            {(["ChatGPT", "Claude", "Other"] as const).map((p) => (
              <button
                key={p}
                type="button"
                aria-label={p}
                title={p}
                aria-pressed={provider === p}
                onClick={() => setProvider(p)}
              >
                <ProviderLogo provider={p} />
              </button>
            ))}
          </div>
        </div>
        <div className="agent-server-label">Server URL</div>
        <CopyValue value={url} label="Copy server URL" />
        <p className="setup-hint">{hint}</p>
      </div>
      <footer className="setup-footer">
        <span>
          <LockKeyhole size={14} /> Read-only access
        </span>
        {destination && (
          <a
            className="connect-open"
            href={destination}
            target="_blank"
            rel="noopener noreferrer"
          >
            Open {provider}
            <ArrowUpRight size={15} />
          </a>
        )}
      </footer>
    </section>
  );
}
