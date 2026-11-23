import { Plug } from "lucide-react";
export type Provider = "Claude" | "ChatGPT" | "Other";
export function ProviderLogo({ provider }: { provider: Provider }) {
  return provider === "Other" ? (
    <Plug size={24} aria-hidden="true" />
  ) : (
    <img
      className={`provider-logo ${provider === "Claude" ? "claude" : ""}`}
      src={`/agents/${provider === "Claude" ? "claude" : "openai"}.svg`}
      alt=""
    />
  );
}
