# Development tasks. Run `just` to list recipes.

# List available recipes.
default:
    @just --list

# --- Dev Postgres, repo-local (Nix shell; no global install) ---

# Initialise and start a Postgres cluster under ./.pgdata on $PGPORT, create the
# zoop role and database, and apply migrations. Idempotent.
pg-start:
    [ -d "$PGDATA" ] || initdb --username=postgres --auth=trust --no-locale --encoding=UTF8 >/dev/null
    pg_ctl status >/dev/null 2>&1 || pg_ctl -o "-p $PGPORT -k /tmp -c listen_addresses=localhost" -l .pgdata/postgres.log start
    psql -U postgres -d postgres -h localhost -p $PGPORT -tc "SELECT 1 FROM pg_roles WHERE rolname='snoop'" | grep -q 1 || psql -U postgres -d postgres -h localhost -p $PGPORT -c "CREATE ROLE zoop LOGIN PASSWORD 'snoop'"
    psql -U postgres -d postgres -h localhost -p $PGPORT -tc "SELECT 1 FROM pg_database WHERE datname='snoop'" | grep -q 1 || psql -U postgres -d postgres -h localhost -p $PGPORT -c "CREATE DATABASE zoop OWNER zoop"
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
    psql postgres://zoop:zoop@localhost:${PGPORT:-5433}/zoop

# --- Database migrations ---

# Apply all pending embedded migrations through the production application path.
migrate config="zoop.dev.toml":
    cargo run -p zoop -- migrate --config {{config}}

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

# Run the service with a config file (default: zoop.dev.toml).
run config="zoop.dev.toml":
    cargo run -p zoop -- run --config {{config}}

# Validate the configuration file.
validate config="zoop.dev.toml":
    cargo run -p zoop -- validate --config {{config}}

# Everything CI runs, locally.
ci: fmt-check clippy test

# Install git pre-commit hooks.
hooks-install:
    pre-commit install

# Install dev tooling not already provided by the Rust toolchain.
install-tools:
    cargo install cargo-audit

# Recovery tests require an explicitly supplied development database. They create
# isolated schemas and fail if the connection is absent or migrations cannot run.
test-db:
    test -n "$ZOOP_TEST_DATABASE_URL"
    cargo test -p zoop-storage -p zoop-api --test reliability -- --ignored
    cargo test -p zoop-storage --test performance -- --ignored
    cargo test -p zoop-storage --test workouts
    cargo test -p zoop-api --test corrections -- --ignored
    cargo test -p zoop-api --test sleep_corrections -- --ignored
    cargo test -p zoop-api --test insights -- --ignored
    cargo test -p zoop-api --test health -- --ignored
    cargo test -p zoop-storage --test profile_weights -- --ignored
    cargo test -p zoop-api --test profile_photo -- --ignored

# Descriptive progress integration contracts against an isolated development schema.
test-progress-db:
    test -n "$ZOOP_TEST_DATABASE_URL"
    cargo test -p zoop-api --test progress -- --ignored
