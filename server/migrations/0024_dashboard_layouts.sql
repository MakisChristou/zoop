-- Private presentation preferences. No public capability or health data.
CREATE TABLE dashboard_layouts (
    account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL REFERENCES device_owners(device_id) ON DELETE CASCADE,
    config JSONB NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    PRIMARY KEY (account_id, device_id)
);
