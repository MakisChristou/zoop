{
  description = "snoop-api development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.cargo
              pkgs.clippy
              pkgs.rustc
              pkgs.rustfmt
              pkgs.rust-analyzer
              pkgs.just
              pkgs.postgresql_18
              pkgs.pkg-config
              pkgs.stdenv.cc
            ];

            # Repo-local Postgres for development (`just pg-start`). Nothing is
            # installed or started globally; the data dir is gitignored.
            PGDATA = "./.pgdata";
            PGHOST = "localhost";
            PGPORT = "5433";
            PGUSER = "snoop";
            PGDATABASE = "snoop";
          };
        }
      );
    };
}
