{
  description = "Zoop read-only web dashboard";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: let
    systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    each = nixpkgs.lib.genAttrs systems;
  in {
    packages = each (system: let pkgs = nixpkgs.legacyPackages.${system}; in {
      default = pkgs.buildNpmPackage {
        pname = "zoop-web";
        version = "0.1.0";
        src = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type: !(builtins.elem (baseNameOf path) [ "node_modules" "dist" "test-results" "playwright-report" ".git" "result" ".direnv" ]);
        };
        nodejs = pkgs.nodejs_24;
        npmDeps = pkgs.importNpmLock { npmRoot = ./.; };
        npmConfigHook = pkgs.importNpmLock.npmConfigHook;
        installPhase = ''mkdir -p $out; cp -r dist/. $out/'';
      };
    });
    devShells = each (system: let pkgs = nixpkgs.legacyPackages.${system}; in {
      default = pkgs.mkShell { packages = [ pkgs.nodejs_24 ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.chromium ]; };
    });
    checks = each (system: { build = self.packages.${system}.default; });
    nixosModules.default = import ./nix/module.nix self;
  };
}
