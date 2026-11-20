# syntax=docker/dockerfile:1
# From the repository root: docker build -f server/crates/zoop/Dockerfile -t zoop-api server
FROM rust:1.100-bookworm@sha256:ade39a710ef85f3506cffcfec3e8a24ba090badef1dff2fb798f71d878833fea AS build
WORKDIR /app
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    cargo build --release --locked -p zoop && cp target/release/zoop /usr/local/bin/zoop

FROM gcr.io/distroless/cc-debian12:nonroot@sha256:9dac0a79194e45a7da0158a9c6da57b217585af0786db3845d1f0ec1a0dd182f AS runtime
WORKDIR /app
LABEL org.opencontainers.image.source="https://github.com/MakisChristou/zoop" \
      org.opencontainers.image.licenses="MIT"
COPY LICENSE /usr/share/licenses/zoop/LICENSE
USER nonroot
COPY --from=build /usr/local/bin/zoop /usr/local/bin/zoop
EXPOSE 8471
ENTRYPOINT ["/usr/local/bin/zoop"]
