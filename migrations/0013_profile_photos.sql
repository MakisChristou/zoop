-- Small private avatars belong in Postgres with the rest of the profile.
CREATE TABLE profile_photos (
 device_id TEXT PRIMARY KEY REFERENCES devices(id),
 jpeg BYTEA NOT NULL CHECK(octet_length(jpeg) BETWEEN 1 AND 262144),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
