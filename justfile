# Development tasks. Run `just` to list recipes.

# List available recipes.
default:
    @just --list

# --- Dev Postgres, repo-local (Nix shell; no global install) ---

# Initialise and start a Postgres cluster under ./.pgdata on $PGPORT, create the
# snoop role and database, and apply migrations. Idempotent.
pg-start:
    [ -d "$PGDATA" ] || initdb --username=postgres --auth=trust --no-locale --encoding=UTF8 >/dev/null
    pg_ctl status >/dev/null 2>&1 || pg_ctl -o "-p $PGPORT -k /tmp -c listen_addresses=localhost" -l .pgdata/postgres.log start
    psql -U postgres -h localhost -p $PGPORT -tc "SELECT 1 FROM pg_roles WHERE rolname='snoop'" | grep -q 1 || psql -U postgres -h localhost -p $PGPORT -c "CREATE ROLE snoop LOGIN PASSWORD 'snoop'"
    psql -U postgres -h localhost -p $PGPORT -tc "SELECT 1 FROM pg_database WHERE datname='snoop'" | grep -q 1 || psql -U postgres -h localhost -p $PGPORT -c "CREATE DATABASE snoop OWNER snoop"
    just migrate

# Stop the repo-local Postgres.
pg-stop:
    pg_ctl stop -m fast

# Stop and wipe the repo-local Postgres.
pg-reset:
    -pg_ctl stop -m fast
    rm -rf "$PGDATA"
    just pg-start

# --- Dev Postgres, Docker (alternative to pg-start) ---

# Start Postgres in Docker, wait for health, and apply migrations.
up:
    docker compose up -d --wait
    just migrate

# Stop the services, keeping data volumes.
down:
    docker compose down

# Stop the services and delete data volumes (wipes the database), then re-create
# the schema so the DB is immediately usable.
reset:
    docker compose down -v
    docker compose up -d --wait
    just migrate

# Tail service logs.
logs:
    docker compose logs -f

# Open a psql shell on the dev database (works for both pg-start and docker).
psql:
    psql postgres://snoop:snoop@localhost:${PGPORT:-5433}/snoop

# --- Database migrations ---

# Apply all pending embedded migrations through the production application path.
migrate config="snoop.dev.toml":
    cargo run -p snoop -- migrate --config {{config}}

# --- Rust workflow ---

build:
    cargo build --workspace

test:
    cargo test --workspace

fmt:
    cargo fmt --all

fmt-check:
    cargo fmt --all --check

clippy:
    cargo clippy --all-targets --all-features -- -D warnings

audit:
    cargo audit

# Run the service with a config file (default: snoop.dev.toml).
run config="snoop.dev.toml":
    cargo run -p snoop -- run --config {{config}}

# Validate the configuration file.
validate config="snoop.dev.toml":
    cargo run -p snoop -- validate --config {{config}}

# Everything CI runs, locally.
ci: fmt-check clippy test

# Install git pre-commit hooks.
hooks-install:
    pre-commit install

# Install dev tooling not already provided by the Rust toolchain.
install-tools:
    cargo install cargo-audit
