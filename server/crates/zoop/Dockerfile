# syntax=docker/dockerfile:1

# Build from the Zoop repository root (server-only build context):
# docker build -f server/crates/zoop/Dockerfile -t zoop server

FROM lukemathwalker/cargo-chef:latest-rust-1.97-bookworm AS chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --locked --package zoop --recipe-path recipe.json
COPY . .
RUN cargo build --release --locked -p zoop

FROM gcr.io/distroless/cc-debian12:nonroot AS runtime
WORKDIR /app
USER nonroot
COPY --from=builder /app/target/release/zoop /usr/local/bin/zoop
EXPOSE 8471
ENTRYPOINT ["/usr/local/bin/zoop"]
