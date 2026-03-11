{
  description = "NixLib";

  inputs = {
    # This is NOT supposed to be overridden in downstream flakes because we want to ensure that all downstream projects
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
      overlays = {
        default = final: prev: {
          ii = prev.ii // { lib = import ./lib.nix final; };
        };
      };

      mkRustOverlay = { loadRustToolchain }: final: prev: {
        ii = prev.ii // {
          rust = import ./rust {
            pkgs = prev;
            inherit loadRustToolchain crane nix-filter docker-spider;
          };
        };
      };

    } // flake-utils.lib.eachDefaultSystem (localSystem:
      let
        pkgs = import nixpkgs-do-not-override { inherit localSystem; };
      in
      {
        braiinsfmt = import ./formatter.nix pkgs;
        formatter = self.braiinsfmt.${localSystem} { };
        packages.braiinsfmt = self.braiinsfmt.${localSystem} { };

        devShells.default = pkgs.mkShell {
          packages = [ (self.braiinsfmt.${localSystem} { }) ];
        };
      });
}
