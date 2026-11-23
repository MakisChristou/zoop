-- Agent credentials are deliberately separate from native upload credentials.
CREATE TABLE agent_clients (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    redirect_uris TEXT[] NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE agent_connections (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    name TEXT NOT NULL,
    scopes TEXT[] NOT NULL,
    history_days INTEGER CHECK (history_days IN (30,90)),
    timezone TEXT NOT NULL,
    client_id TEXT REFERENCES agent_clients(id),
    resource TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ
);
CREATE INDEX agent_connections_account ON agent_connections(account_id);
CREATE TABLE agent_credentials (
    digest TEXT PRIMARY KEY,
    connection_id BIGINT NOT NULL REFERENCES agent_connections(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('key','code','access','refresh')),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed BOOLEAN NOT NULL DEFAULT false,
    redirect_uri TEXT,
    challenge TEXT
);
CREATE INDEX agent_credentials_connection ON agent_credentials(connection_id);
-- Password recovery, disabling and ownership changes invalidate all grants even
-- if an operator changes the records outside the HTTP API.
CREATE FUNCTION invalidate_agent_account() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.password_hash IS DISTINCT FROM OLD.password_hash OR NOT NEW.enabled THEN
  UPDATE agent_connections SET revoked_at=now() WHERE account_id=NEW.id AND revoked_at IS NULL;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER agent_account_changed AFTER UPDATE OF password_hash,enabled ON accounts
FOR EACH ROW EXECUTE FUNCTION invalidate_agent_account();
CREATE FUNCTION invalidate_agent_device() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE agent_connections SET revoked_at=now() WHERE account_id=OLD.account_id AND device_id=OLD.device_id AND revoked_at IS NULL;
 RETURN OLD;
END $$;
CREATE TRIGGER agent_device_changed AFTER DELETE OR UPDATE ON device_owners
FOR EACH ROW EXECUTE FUNCTION invalidate_agent_device();
