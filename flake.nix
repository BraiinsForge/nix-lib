{
  description = "NixLib";

  inputs = {
    # This is NOT supposed to be overriden in downstream flakes because we want to ensure that all downstream projects
    # are using the same versions of formatters.
    nixpkgs-do-not-override.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter"; # TODO: replace with filesets
    crane.url = "github:ipetkov/crane/v0.20.2";
    docker-spider = {
      url = "git+ssh://git@gitlab.ii.zone/bos/docker-spider";
      inputs.nixpkgs.follows = "nixpkgs-do-not-override";
      inputs.flake-utils.follows = "flake-utils";
      inputs.crane.follows = "crane";
    };
  };

  outputs = { self, nixpkgs-do-not-override, flake-utils, crane, docker-spider, nix-filter, ... }:
    {
      mkOverlay = { loadRustToolchain }:
        final: prev: rec {
          ii.lib = self.mkLib final;
          ii.rustToolchain = loadRustToolchain final;
          ii.rust = ii.lib.mkRustLib {
            craneLib = ii.lib.craneLib.overrideToolchain loadRustToolchain;
          };
        };

      mkLib = pkgs:
        let
          localSystem = pkgs.stdenv.buildPlatform.system;

          craneLibOrig = crane.mkLib pkgs;
          craneLibWithRegistries = craneLibOrig.appendCrateRegistries (import ./registries.nix craneLibOrig);
        in
        {
          craneLib = craneLibWithRegistries;

          mkRustLib = { craneLib ? craneLibWithRegistries }: import ./rust {
            inherit pkgs craneLib docker-spider nix-filter localSystem;
          };

          mkCrossPkgs = imported_nixpkgs: { arch, extras ? { } }:
            let
              base = {
                inherit localSystem;
                crossSystem.config = arch;
                config.allowUnsupportedSystem = true;
              };
            in
            imported_nixpkgs (pkgs.lib.recursiveUpdate base extras);

        } // import ./lib.nix pkgs;
    } // flake-utils.lib.eachDefaultSystem (localSystem:
      let
        pkgs = import nixpkgs-do-not-override { inherit localSystem; };
      in
      {
        braiinsfmt = import ./formatter.nix pkgs;
        formatter = self.braiinsfmt.${localSystem} { };
      });
}
