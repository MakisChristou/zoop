{
  description = "snoop-api: self-hosted backend for WHOOP 5.0 / MG straps";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = self.packages.${system}.snoop;
          snoop = pkgs.rustPlatform.buildRustPackage {
            pname = "snoop";
            version = "0.1.0";
            src = pkgs.lib.cleanSourceWith {
              src = ./.;
              filter =
                path: type:
                let
                  base = baseNameOf path;
                in
                !(builtins.elem base [
                  "refs"
                  "captures"
                  ".pgdata"
                  "target"
                  ".direnv"
                ]);
            };
            cargoLock.lockFile = ./Cargo.lock;
            cargoBuildFlags = [ "-p" "snoop" ];
            doCheck = false; # tests need no database, but the build sandbox has no network for sqlx macros either way
            nativeBuildInputs = [ pkgs.pkg-config ];
            meta = {
              description = "Self-hosted backend for WHOOP 5.0 / MG straps";
              license = pkgs.lib.licenses.mit;
              mainProgram = "snoop";
            };
          };
        }
      );

      nixosModules.default = import ./nix/module.nix self;

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
