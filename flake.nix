{
  description = "NixLib";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    docker-spider = {
      url = "git+ssh://git@gitlab.ii.zone/bos/docker-spider";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.crane.follows = "crane";
    };
    nix-filter = {
      url = "github:numtide/nix-filter";
    };
  };

  outputs = { self, nixpkgs, flake-utils, crane, docker-spider, nix-filter, ... }:
    {
      mkLib = pkgs:
        let
          localSystem = pkgs.stdenv.buildPlatform.system;

          craneLibOrig = crane.mkLib pkgs;
          craneLibWithRegistries = craneLibOrig.appendCrateRegistries (import ./registries.nix craneLibOrig);

          utils = import ./utils.nix { inherit nixpkgs localSystem; };
        in
        {
          craneLib = craneLibWithRegistries;
          mkCrossPkgs = utils.mkNixpkgs;

          mkRustLib = { craneLib ? craneLibWithRegistries }: import ./rust {
            inherit pkgs craneLib docker-spider nix-filter localSystem;
          };
        };
    } // flake-utils.lib.eachDefaultSystem (localSystem:
      let
        pkgs = import nixpkgs { inherit localSystem; };
      in
      {
        formatter = pkgs.nixpkgs-fmt;
      });
}
