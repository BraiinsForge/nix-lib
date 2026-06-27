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

  fixtureSrc = ./source-graph-fixture;

  has = path: files: builtins.elem path files;
  assertMsg = msg: ok: if ok then true else throw msg;

  profile =
    (pkgs.ii.rust.mkWorkspaceConfig {
      src = fixtureSrc;
    }).mkBuildProfile { };

  crate = pkgs.ii.rust.defineCrate {
    path = "member";
    packageName = "member";
    binName = false;
  };

  workspaceFiles = profile.build.passthru.srcFiles;
  crateFiles = (profile.buildCrate crate { }).passthru.srcFiles;
in
assert assertMsg "default source should include root Cargo.toml"
  (has "Cargo.toml" workspaceFiles);
assert assertMsg "default source should include package metadata includes"
  (has "member/extra.txt" workspaceFiles);
assert assertMsg "default source should ignore standalone nested Cargo.toml"
  (!has "nested-workspace/Cargo.toml" workspaceFiles);
assert assertMsg "default source should ignore standalone nested Cargo.lock"
  (!has "nested-workspace/Cargo.lock" workspaceFiles);
assert assertMsg "crate source should include root Cargo.toml"
  (has "Cargo.toml" crateFiles);
assert assertMsg "crate source should include package metadata includes"
  (has "member/extra.txt" crateFiles);
assert assertMsg "crate source should ignore standalone nested Cargo.toml"
  (!has "nested-workspace/Cargo.toml" crateFiles);
assert assertMsg "crate source should ignore standalone nested Cargo.lock"
  (!has "nested-workspace/Cargo.lock" crateFiles);
true
