import { Camera, Plug, Share2, Shield, User } from "lucide-react";
import { type ReactNode } from "react";
import { type Account } from "./data";

const sections = [
  { id: "profile", label: "Profile", icon: User, href: "#Settings/profile" },
  {
    id: "agents",
    label: "Connected apps",
    icon: Plug,
    href: "#Settings/agents",
  },
  { id: "shares", label: "Shared dashboards", icon: Share2, href: "#Shares" },
  { id: "admin", label: "Admin", icon: Shield, href: "#Admin" },
] as const;
export type SettingsTab = (typeof sections)[number]["id"];

export function Settings({
  tab,
  account,
  device,
  children,
}: {
  tab: SettingsTab;
  account: Account;
  device?: string;
  children?: ReactNode;
}) {
  const available = sections.filter(
    (s) => s.id !== "admin" || account.is_admin,
  );
  return (
    <section className="settings-layout">
      <nav className="settings-nav" aria-label="Settings">
        <h2>Settings</h2>
        {available.map(({ id, label, icon: Icon, href }) => (
          <a
            key={id}
            href={href}
            aria-current={id === tab ? "page" : undefined}
          >
            <Icon size={17} />
            {label}
          </a>
        ))}
      </nav>
      <div className="settings-content">
        <select
          className="settings-picker"
          aria-label="Settings section"
          value={sections.find((s) => s.id === tab)?.href}
          onChange={(e) => {
            location.hash = e.target.value;
          }}
        >
          {available.map((s) => (
            <option key={s.id} value={s.href}>
              {s.label}
            </option>
          ))}
        </select>
        {tab === "profile" ? (
          <>
            <h1>Profile</h1>
            <section className="panel settings-profile">
              <div>
                <span className="muted">Account</span>
                <p>{account.email}</p>
              </div>
              <button
                disabled={!device}
                onClick={() =>
                  window.dispatchEvent(new Event("zoop:edit-photo"))
                }
              >
                <Camera size={17} />
                Change photo
              </button>
            </section>
          </>
        ) : (
          children
        )}
      </div>
    </section>
  );
}
