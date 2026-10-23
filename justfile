# Development tasks. Run `just` to list recipes.

# List available recipes.
default:
    @just --list

# --- Dev services (Postgres) ---

# Start Postgres, wait for health, and apply migrations through the snoop binary
# (idempotent — the embedded migrator skips applied versions).
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

# Open a psql shell on the dev database.
psql:
    docker compose exec postgres psql -U snoop -d snoop

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
