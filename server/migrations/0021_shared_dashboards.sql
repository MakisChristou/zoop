-- Revocable, account-owned read-only views. No account credentials are shared.
CREATE TABLE shared_dashboards (
 id bigserial PRIMARY KEY,
 account_id bigint NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 device_id text NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
 token_hash text NOT NULL UNIQUE,
 -- Kept for the owner's Copy link action; never included in public responses/logs.
 token text NOT NULL,
 config jsonb NOT NULL,
 password_hash text,
 enabled boolean NOT NULL DEFAULT true,
 expires_at timestamptz,
 revision bigint NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX shared_dashboards_owner ON shared_dashboards(account_id,id);
