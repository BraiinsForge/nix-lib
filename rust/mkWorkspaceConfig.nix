# inherited args
inputs:
# this fn's args
{ src
, env ? { }
, rustFlags ? [ ]
, nativeDeps ? _: [ ]
, targetDeps ? _: [ ]
, addSuffixToBinaries ? false
, enableRustFlagsHack ? false
, disableKeepGoing ? false
, wasm-bindgen-cli ? null
}:
let
  pkgs = inputs.pkgs;
  nix-filter = inputs.nix-filter;
in
with builtins;
let
  workspace_src = builtins.path { path = src; name = "workspace-src"; };

  manifests_src = nix-filter.lib.filter {
    root = workspace_src;
    include = [
      (nix-filter.lib.and
        nix-filter.lib.isDirectory
        (_: p: _: ((match ".*/(src|assets|proto)/.*" (toString p)) == null))
      )
      (nix-filter.lib.matchExt "toml")
      "${workspace_src}/Cargo.toml"
      "${workspace_src}/Cargo.lock"
      "${workspace_src}/.cargo"
    ];
  };

  ####################################################################
  # A helper derivation containing only Cargo manifests
  #
  # To be able to calculate which sources are relevant to a particular
  # crate in a workspace, we need to be able to see these files, but
  # if we referred to `${self}` directly (meaning the original repo),
  # we would do no caching at all since the sources would change
  # every time and Nix would invalidate the cache.
  #
  # We only need the Cargo manifests for docker-spider to function, so
  # we can just cut them out into its own derivation and use it as the
  # environment to run docker-spider.
  #
  # This means that so long as only sources are changing anywhere in
  # the repo, we will only be rebuilding precisely what we need, saving
  # more CPU time.
  #
  # The downside is that changes to Cargo files mean that we will make
  # the cache no longer valid, and that will trigger a full rebuild.
  #
  # However, due to the transferrable nature of Nix store and deterministic
  # builds, we could set up nix store sharing and completely sidestep
  # this issue - if you already built the project in Nix locally, CI
  # would just pick up the derivation artifacts you produce and finish
  # in a couple seconds.
  #
  # This would be safe, since the environment is 100% controlled and
  # identical.
  ####################################################################
  manifestSearch = pkgs.stdenv.mkDerivation {
    name = "cargo-manifests-only";
    nativeBuildInputs = with pkgs; [ fd ];
    src = manifests_src;
    ################################
    # Since Cargo will fail to parse
    # a manifest that has absolutely
    # no sources, we need to make a
    # src folder and create a dummmy
    # source file so that we get the
    # full metadata
    ################################
    buildPhase = ''
      mkdir $out
      cp -r ** $out
      cd $out
      for manifest in $(fd Cargo.toml); do
        pushd $(dirname $manifest)
        mkdir -p src
        touch src/lib.rs
        popd
      done
    '';
    installPhase = "true";
  };
in
{
  mkBuildProfile = import ./mkBuildProfile.nix inputs {
    src = workspace_src;
    inherit env rustFlags nativeDeps targetDeps addSuffixToBinaries enableRustFlagsHack disableKeepGoing wasm-bindgen-cli;
    inherit manifestSearch;
  };

  # not used normally but can be used for debugging purposes
  internal = {
    inherit manifestSearch;
  };
}
