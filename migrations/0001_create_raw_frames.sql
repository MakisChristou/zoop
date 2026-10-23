-- Raw frames are the source of truth. Everything else is derived and rebuilt by the
-- worker when `decoded_proto` lags behind the current protocol version.

CREATE TABLE devices (
    id          TEXT PRIMARY KEY,                 -- strap serial (DIS 0x2A25)
    model       TEXT NOT NULL,                    -- 'MG' | '5.0'
    firmware    TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE raw_frames (
    id             BIGSERIAL PRIMARY KEY,
    device_id      TEXT NOT NULL REFERENCES devices (id),
    client_seq     BIGINT NOT NULL,               -- phone-assigned, monotonic per device
    channel        SMALLINT NOT NULL,             -- fd4b000x notify channel: 3,4,5,7
    received_at    TIMESTAMPTZ NOT NULL,          -- phone wall clock at receipt
    bytes          BYTEA NOT NULL,                -- one complete, CRC-valid frame
    uploaded_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    decoded_proto  INTEGER,                       -- snoop_proto::PROTO_VERSION applied; NULL = pending
    UNIQUE (device_id, client_seq)                -- ingest is idempotent across retries
);

CREATE INDEX raw_frames_pending_idx ON raw_frames (id) WHERE decoded_proto IS NULL;
