# NixOS module for snoop-api.
#
#   services.snoop = {
#     enable = true;
#     port = 8471;
#     tokenFile = "/run/secrets/snoop-token";   # contains only the bearer token
#     openFirewall = true;
#   };
#
# Runs the service as a dedicated user against the host's local Postgres (a database
# and role are created on whatever instance and port services.postgresql runs),
# applies migrations before start, and reads the ingest token from a file so it never
# enters the Nix store.
flake:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.snoop;
  configFile = pkgs.writeText "snoop.toml" ''
    [server]
    bind = "${cfg.bind}:${toString cfg.port}"
    ingest_token = "placeholder-replaced-at-start"

    [storage]
    postgres_url = "postgres:///${cfg.database}?host=/run/postgresql&port=${toString config.services.postgresql.settings.port}"

    [worker]
    poll_interval_ms = ${toString cfg.pollIntervalMs}
    batch_size = ${toString cfg.batchSize}
    analysis_interval_s = ${toString cfg.analysisIntervalS}
  '';
in
{
  options.services.snoop = {
    enable = lib.mkEnableOption "snoop-api, the self-hosted WHOOP backend";

    package = lib.mkOption {
      type = lib.types.package;
      default = flake.packages.${pkgs.stdenv.hostPlatform.system}.snoop;
      description = "The snoop package to run.";
    };

    bind = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address the HTTP API binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8471;
      description = "Port the HTTP API listens on.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the bearer token the iOS app presents. Read at start; not copied to the store.";
    };

    database = lib.mkOption {
      type = lib.types.str;
      default = "snoop";
      description = "Local Postgres database (and role) name.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the API port in the firewall.";
    };

    pollIntervalMs = lib.mkOption {
      type = lib.types.int;
      default = 5000;
    };

    batchSize = lib.mkOption {
      type = lib.types.int;
      default = 500;
    };

    analysisIntervalS = lib.mkOption {
      type = lib.types.int;
      default = 900;
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      ensureDatabases = [ cfg.database ];
      ensureUsers = [
        {
          name = cfg.database;
          ensureDBOwnership = true;
        }
      ];
    };

    users.users.${cfg.database} = {
      isSystemUser = true;
      group = cfg.database;
    };
    users.groups.${cfg.database} = { };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.snoop = {
      description = "snoop-api";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "postgresql.service"
      ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        User = cfg.database;
        Group = cfg.database;
        RuntimeDirectory = "snoop";
        LoadCredential = "token:${cfg.tokenFile}";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
      environment.RUST_LOG = "info";
      script = ''
        # The token is injected from the credential file; the TOML in the store holds a placeholder.
        export SNOOP_SERVER__INGEST_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/token")"
        ${cfg.package}/bin/snoop migrate --config ${configFile}
        exec ${cfg.package}/bin/snoop run --config ${configFile}
      '';
    };
  };
}
