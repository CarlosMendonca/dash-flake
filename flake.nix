{
  description =
    "Pinned Dart & Flutter SDK binaries (stable/beta/dev) for x86_64-linux and aarch64-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      dartData = builtins.fromJSON (builtins.readFile ./data/dart.json);
      flutterData = builtins.fromJSON (builtins.readFile ./data/flutter.json);

      mkPackages = pkgs: import ./lib/mk-packages.nix {
        inherit pkgs dartData flutterData;
        lib = pkgs.lib;
      };
    in
    {
      # Fold every dart_*/flutter_* package (and aliases) into a consumer's nixpkgs.
      # Build from `prev` (these are leaf packages that don't reference other
      # dash packages); using `final` here would recurse through stdenv.
      overlays.default = _final: prev: mkPackages prev;
    }
    // flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # `nix run .#update` regenerates data/*.json from the Google archives.
        update = pkgs.writeShellScriptBin "dash-update" ''
          export PATH=${lib.makeBinPath [
            pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnused pkgs.gnugrep
          ]}:$PATH
          exec ${pkgs.bash}/bin/bash ${./updater/update.sh} "$@"
        '';
        lib = pkgs.lib;
      in
      {
        packages = mkPackages pkgs;

        apps.update = {
          type = "app";
          program = "${update}/bin/dash-update";
        };
        apps.default = self.apps.${system}.update;
      });
}
