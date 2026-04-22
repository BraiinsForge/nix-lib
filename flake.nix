{
  description = "NixLib";

  inputs = {
    # This is NOT supposed to be overridden in downstream flakes because we want to ensure that all downstream projects
    # are using the same versions of formatters.
    nixpkgs-do-not-override.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter"; # TODO: replace with filesets
    fenix.url = "github:nix-community/fenix";
    crane.url = "github:ipetkov/crane/v0.20.2";
    docker-spider = {
      url = "git+ssh://git@gitlab.ii.zone/bos/docker-spider";
      inputs.nixpkgs.follows = "nixpkgs-do-not-override";
      inputs.flake-utils.follows = "flake-utils";
      inputs.crane.follows = "crane";
    };
    nix-source-info.url = "git+ssh://git@gitlab.ii.zone/nix/source-info";
  };

  outputs = { self, nixpkgs-do-not-override, flake-utils, crane, fenix, docker-spider, nix-filter, nix-source-info, ... }:
    rec {
      overlays = {
        default = final: prev: {
          ii = prev.ii // { lib = import ./lib.nix final; };
        };
        downgradeUpxForBeagleBone = final: prev:
          if prev.stdenv.hostPlatform.isLinux then {
            # Downgrade UPX to 4.2.4, because 5.0.0 segfaults on beaglebone and 5.0.1 returns `UPX-5.0 wants memfd_create(), or needs /dev/shm(,O_TMPFILE,)`
            # (nixpkgs commit hash source: https://history.nix-packages.com/package/upx/4.2.4)
            upx = (builtins.getFlake "github:NixOS/nixpkgs/4abc8841bb6d4dd1b11a032b04a87bd2948502d9").legacyPackages.${prev.hostPlatform.system}.upx;
          } else { };
      };

      mkRustOverlay = { loadRustToolchain }: final: prev: {
        ii = prev.ii // rec {
          rust = import ./rust {
            pkgs = prev;
            inherit loadRustToolchain crane fenix nix-filter docker-spider;
            patchSourceInfo = nix-source-info.lib.patchSourceInfo prev;
          };
          rustToolchain = final.lib.warn "`rustToolchain` is deprecated, please use `rust.toolchain` instead" rust.toolchain;
        };
      };

      mkRustOverlayFromToolchainFile = { file, sha256 }: mkRustOverlay {
        loadRustToolchain = p: p.fenix.fromToolchainFile {
          inherit file sha256;
        };
      };

    } // flake-utils.lib.eachDefaultSystem (localSystem:
      let
        pkgs = import nixpkgs-do-not-override { inherit localSystem; };
      in
      {
        formatter = self.braiinsfmt.${localSystem} {
          justfile = true;
          config.exclude = [ "tests/fmt/dirty/*" ];
        };

        braiinsfmt = import ./formatter.nix pkgs;
        packages.braiinsfmt = self.braiinsfmt.${localSystem} { };

        braiinschk = import ./checks.nix pkgs;
        packages.braiinschk = self.braiinschk.${localSystem} { };

        devShells.default = pkgs.mkShell {
          packages = [
            (self.braiinsfmt.${localSystem} { justfile = true; })
            (self.braiinschk.${localSystem} {
              justfile = true;
              config.exclude = [ "tests/fmt/dirty/*" ];
            })
          ];
        };
      });
}
