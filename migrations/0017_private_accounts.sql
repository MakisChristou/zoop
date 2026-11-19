-- Opt-in multi-user access. No existing health records or raw frames are changed.
CREATE TABLE accounts (
    id BIGSERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL CHECK (email = lower(trim(email))),
    password_hash TEXT NOT NULL,
    is_admin BOOLEAN NOT NULL DEFAULT false,
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Reservation before first ingest is intentional: users cannot claim arbitrary serials.
CREATE TABLE device_owners (
    device_id TEXT PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(id)
);
CREATE INDEX device_owners_account_idx ON device_owners(account_id);
CREATE TABLE account_tokens (
    digest TEXT PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE web_sessions (
    digest TEXT PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(id),
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX web_sessions_account_idx ON web_sessions(account_id);
CREATE INDEX web_sessions_expiry_idx ON web_sessions(expires_at);
CREATE TABLE login_limits (
    bucket TEXT PRIMARY KEY,
    window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
    attempts INTEGER NOT NULL
);
CREATE INDEX raw_frames_uploaded_at_idx ON raw_frames(uploaded_at);
