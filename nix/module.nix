flake:
{ config, lib, pkgs, ... }:
let cfg = config.services.zoop-web;
headers = ''
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy no-referrer always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" always;
      '';
in {
  options.services.zoop-web = {
    enable = lib.mkEnableOption "Zoop read-only web dashboard";
    package = lib.mkOption { type = lib.types.package; default = flake.packages.${pkgs.stdenv.hostPlatform.system}.default; };
    domain = lib.mkOption { type = lib.types.str; description = "HTTPS hostname for the dashboard."; };
    apiUrl = lib.mkOption { type = lib.types.str; default = "http://127.0.0.1:8471"; description = "Private Zoop API upstream with private-account mode enabled."; };
    enableACME = lib.mkOption { type = lib.types.bool; default = true; };
  };
  config = lib.mkIf cfg.enable {
    services.nginx.enable = true;
    services.nginx.virtualHosts.${cfg.domain} = {
      forceSSL = true;
      enableACME = cfg.enableACME;
      root = cfg.package;
      extraConfig = headers;
      locations."/" = { tryFiles = "$uri /index.html"; extraConfig = headers + "add_header Cache-Control no-store always;"; };
      locations."/assets/".extraConfig = "expires 1y;";
      locations."/v1/" = { proxyPass = cfg.apiUrl; extraConfig = headers + ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
        client_max_body_size 2m;
        add_header Cache-Control no-store always;
      ''; };
    };
  };
}
