# syntax=docker/dockerfile:1

# Build from the workspace root:
# docker build -f crates/snoop/Dockerfile -t snoop .

FROM lukemathwalker/cargo-chef:latest-rust-1.97-bookworm AS chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --locked --package snoop --recipe-path recipe.json
COPY . .
RUN cargo build --release --locked -p snoop

FROM gcr.io/distroless/cc-debian12:nonroot AS runtime
WORKDIR /app
USER nonroot
COPY --from=builder /app/target/release/snoop /usr/local/bin/snoop
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/snoop"]
