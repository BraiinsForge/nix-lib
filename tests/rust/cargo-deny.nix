{ repoRoot ? ../.. }:
let
  flake = builtins.getFlake (toString repoRoot);
  system = builtins.currentSystem;
  pkgs = import flake.inputs.nixpkgs-do-not-override {
    localSystem = system;
    overlays = [
      flake.overlays.default
      (flake.mkRustOverlay {
        loadRustToolchain = p: p.fenix.stable.minimalToolchain;
      })
    ];
  };

  profile =
    (pkgs.ii.rust.mkWorkspaceConfig {
      src = ./source-graph-fixture;
    }).mkBuildProfile { };

  cargoDeny = profile.mkCargoDeny {
    config = "../deny.toml";
    checks = [ "sources" ];
  };
in
assert pkgs.lib.assertMsg
  (pkgs.lib.hasInfix "deny  check --config ../deny.toml sources" cargoDeny.buildPhase)
  "cargo-deny config must follow the check subcommand";
true
