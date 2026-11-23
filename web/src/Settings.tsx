import { Camera, Plug, Share2, User } from "lucide-react";
import { type Account } from "./data";
import { AgentConnections } from "./AgentConnections";
import { Sharing } from "./SharingSettings";
export type SettingsTab = "profile" | "agents" | "shares";
export function Settings({
  tab,
  account,
  device,
  devices,
  connect,
}: {
  tab: SettingsTab;
  account: Account;
  device?: string;
  devices: string[];
  connect: () => void;
}) {
  return (
    <section className="settings-page">
      <h1>Settings</h1>
      <div className="settings-layout">
        <nav className="settings-nav" aria-label="Settings">
          {(
            [
              ["profile", "Profile", User],
              ["agents", "Connected apps", Plug],
              ["shares", "Shared dashboards", Share2],
            ] as const
          ).map(([id, label, Icon]) => (
            <a
              key={id}
              href={id === "shares" ? "#Shares" : `#Settings/${id}`}
              aria-current={tab === id ? "page" : undefined}
            >
              <Icon size={17} />
              {label}
            </a>
          ))}
        </nav>
        <div className="settings-content">
          {tab === "agents" ? (
            <AgentConnections
              device={device}
              devices={devices}
              connect={connect}
            />
          ) : tab === "shares" ? (
            device ? (
              <Sharing device={device} />
            ) : (
              <p>Link a band to share your dashboard.</p>
            )
          ) : (
            <>
              <h2>Profile</h2>
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
          )}
        </div>
      </div>
    </section>
  );
}
