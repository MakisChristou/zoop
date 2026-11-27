import { useState } from "react";
import { Copy } from "lucide-react";
export function CopyValue({
  value,
  label,
  secret = false,
}: {
  value: string;
  label: string;
  secret?: boolean;
}) {
  const [copied, setCopied] = useState(false),
    [error, setError] = useState(""),
    [revealed, setRevealed] = useState(false);
  return (
    <div className="agent-copy">
      <input
        aria-label={secret ? "Access key" : "MCP server URL"}
        readOnly
        type={secret && !revealed ? "password" : "text"}
        value={value}
        autoComplete="off"
        spellCheck={false}
      />
      <button
        aria-label={label}
        onClick={async () => {
          try {
            await navigator.clipboard.writeText(value);
            setCopied(true);
            setError("");
          } catch {
            // Clipboard access requires a secure browser context. LAN HTTP users
            // still need a selectable, readable key after explicitly asking to copy.
            setRevealed(true);
            setError("Copy unavailable. Select the value to copy it.");
          }
        }}
      >
        <Copy size={16} />
        {!secret && <span className="copy-caption">Copy</span>}
      </button>
      <span role="status">{error || (copied ? "Copied" : "")}</span>
    </div>
  );
}
