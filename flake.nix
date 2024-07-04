{
  description = "NixLib";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";

    crane = {
      url = "github:ipetkov/crane/v0.17.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    docker-spider = {
      url = "git+ssh://git@gitlab.ii.zone/bos/docker-spider";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      # docker-spider flake uses something that's deprecated in newer crane
      inputs.crane.url = "github:ipetkov/crane/v0.16.3";
    };
  };

  outputs = { self, nixpkgs, flake-utils, crane, docker-spider, nix-filter, ... }:
    {
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
        pkgs = import nixpkgs { inherit localSystem; };
      in
      {
        formatter = pkgs.nixpkgs-fmt;
      });
}
