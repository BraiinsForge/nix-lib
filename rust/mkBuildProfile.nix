# inherited args
inputs: workspace:
# this fn's args
{ pkgs ? inputs.pkgs
  # https://crane.dev/API.html#cranelibstdenvselector
, stdenvSelector ? (p: p.stdenv)
, loadRustToolchain ? inputs.loadRustToolchain
, rustCrossTargetOverride ? null
, rustProfile ? "dev"
, minimalDeps ? false
, denix ? false
, upx ? "none"
, env ? { }
, crateEnv ? { }
, nativeDeps ? _: [ ]
, targetDeps ? _: [ ]
, runtimeDeps ? [ ]
, runtimeEnv ? { }
, wrapNixGL ? false
, includeExtraSrc ? workspace.includeExtraSrc
  # Cargo feature selection applied to the workspace-level `build`, `clippy`,
  # `test`, `nextest` derivations and to their shared dependency cache. Without
  # this, those derivations run with default features only — bins gated by
  # `required-features` are silently skipped, which hides type errors and lints.
, features ? [ ]
, noDefaultFeatures ? false
, allFeatures ? false
, sccache ? workspace.sccache
}:
assert !allFeatures || (features == [ ] && !noDefaultFeatures); # `allFeatures` is mutually exclusive with explicit feature selection
let lib = pkgs.lib; in
let pkgs' = pkgs; in
let pkgs = (pkgs'.extend inputs.fenix.overlays.default); in
let
  mkCraneLib = { pkgs, loadRustToolchain, registries ? _: [ ], stdenvSelector ? (p: p.stdenv) }:
    let
      craneLib1 = inputs.crane.mkLib pkgs;
      craneLib2 = craneLib1.overrideToolchain loadRustToolchain;
      craneLib3 = craneLib2.appendCrateRegistries (registries craneLib1);
      craneLib4 = craneLib3.overrideScope (_: _: { inherit stdenvSelector; });
    in
    craneLib4;

  craneLib = mkCraneLib {
    inherit pkgs loadRustToolchain stdenvSelector;
    registries = cl: [
      (cl.registryFromSparse {
        indexUrl = "http://registry.ii.zone/api/v1/crates/";
        configSha256 = "8ae51bd02f2645c885a8595e2c0bda4baf2855992b38b57328b444b9132ef1df";
      })
    ];
  };

  selectedStdenv = stdenvSelector pkgs;

  featuresArgs =
    let
      parts = lib.optional noDefaultFeatures "--no-default-features"
        ++ lib.optional allFeatures "--all-features"
        ++ lib.optional (features != [ ]) ("--features " + lib.concatStringsSep "," features);
    in
    lib.concatStringsSep " " parts;

  # set of arguments that must be the same for `buildDepsOnly` and `buildPackage`, to prevent full workspace rebuilds in `buildPackage`
  commonArgs =
    {
      nativeBuildInputs = (workspace.nativeDeps pkgs.pkgsBuildBuild) ++ (nativeDeps pkgs.pkgsBuildBuild);
      buildInputs = (workspace.targetDeps pkgs) ++ (targetDeps pkgs) ++ (lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ]);
      CARGO_PROFILE = rustProfile;
      strictDeps = true;
      CARGO_INCREMENTAL = "0"; # incremental compilation is always counterproductive in sandbox
    }
    // workspace.env
    // env
    // lib.optionalAttrs (rustCrossTargetOverride != null) { CARGO_BUILD_TARGET = rustCrossTargetOverride; }
    // lib.optionalAttrs sccache {
      # this only does something if the build machine sets up the redis socket via extra-sandbox-paths
      RUSTC_WRAPPER = pkgs.pkgsBuildBuild.writeShellScript "rustc-wrapper-sccache" ''
        sock=/run/redis-sccache/redis.sock
        if test -S "$sock" && test -w "$sock"; then
          # Workaround for UDS parsing bug: https://github.com/mozilla/sccache/issues/2214
          export SCCACHE_REDIS_ENDPOINT="unix://dummy$sock"
          export SCCACHE_DIR="$TMPDIR/sccache"
          exec ${lib.getExe pkgs.pkgsBuildBuild.sccache} "$@"
        else
          exec "$@"
        fi
      '';
      postPhases = [ "sccacheStatsPhase" ];
      sccacheStatsPhase = ''
        sock=/run/redis-sccache/redis.sock
        if test -S "$sock" && test -w "$sock"; then
          ${lib.getExe pkgs.pkgsBuildBuild.sccache} --show-stats --stats-format=json | ${lib.getExe pkgs.pkgsBuildBuild.jq} -r '
            .stats
            | (.cache_hits.counts.Rust // 0) as $hits
            | (.cache_misses.counts.Rust // 0) as $misses
            | if ($hits + $misses) == 0
              then "no rust compilations recorded by sccache"
              else "sccache hit rate: \(100 * $hits / ($hits + $misses) * 100 | round / 100)%"
              end
          '
        else
          echo "sccache not active (no cache backend available)"
        fi
      '';
    };

  workspacePath = workspace.workspacePath;
  workspacePrefix = lib.optionalString (workspacePath != "") "${workspacePath}/";

  # Using this and not workspace.src, ensures the
  # derivations do not get rebuilt on any changes
  workspaceCargoLock =
    if workspacePath == "" then null
    else
      builtins.path {
        path = workspace.src + "/${workspacePrefix}Cargo.lock";
        name = "workspace-cargo-lock";
      };

  dummySrc = craneLib.mkDummySrc ({
    src = workspace.src;
  } // lib.optionalAttrs (workspacePath != "") {
    extraDummyScript = ''
      cp ${workspaceCargoLock} $out/${workspacePrefix}Cargo.lock
    '';
  });

  workspacePostUnpack = lib.optionalString (workspacePath != "") ''
    sourceRoot="$sourceRoot/${workspacePath}"
  '';

  # Transitive closure of local path-deps for a crate dir, including the crate itself.
  localDepClosure =
    let
      # Discard unwanted string context added by `readFile` just because the JSON contains store paths
      cargoMetadata = builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile (pkgs.runCommand "cargo-metadata.json"
        { nativeBuildInputs = [ craneLib.cargo ]; }
        ''
          export CARGO_HOME="$(mktemp -d)"
          cd ${dummySrc}/${workspacePrefix}
          cargo metadata --no-deps --format-version 1 --offline >"$out"
        '')));

      metaRel = abs: lib.removePrefix "/" (lib.removePrefix cargoMetadata.workspace_root abs);

      localDepEdges = lib.listToAttrs (map
        (pkg: {
          name = metaRel (dirOf pkg.manifest_path);
          value = map (d: metaRel d.path) (builtins.filter (d: (d.path or null) != null) pkg.dependencies);
        })
        cargoMetadata.packages);

      visit = acc: cur:
        if builtins.elem cur acc then acc
        else builtins.foldl' visit (acc ++ [ cur ]) (localDepEdges.${cur} or [ ]);
    in
    dir: visit [ ] dir;

  # Vendor all Cargo dependencies once per profile.
  cargoVendorDir = craneLib.vendorCargoDeps ({
    src = workspace.src;
  } // lib.optionalAttrs (workspacePath != "") {
    cargoLock = workspaceCargoLock;
  });

  ####################################################################
  # build all dependencies of all packages in the virtual workspace
  # (equivalent to passing --workspace)
  #
  # This is similar to what cargo-chef does in the bos-main pipeline.
  # Most dependencies are independent from the sources your crate has,
  # so we can do a clean build with a dummy sources, and then we can
  # transplant the target/ folder into the actual build of the crate,
  # saving a lot of time.
  ####################################################################
  commonCargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
    inherit cargoVendorDir;
    inherit dummySrc;
    pname = "workspace";
    version = "0.0.0";
    cargoExtraArgs = lib.strings.trim "--locked --all-targets ${featuresArgs}";
    doCheck = false;
    postUnpack = workspacePostUnpack;
  });

  mkShell =
    { name ? "build-env"
    , packages ? [ ]
    , inputsFrom ? [ ]
    , shellHook ? ""
    , env ? { }
    }: (pkgs.mkShell.override { stdenv = selectedStdenv; }) ((removeAttrs commonArgs [ "CARGO_INCREMENTAL" ]) // {
      inherit name;
      packages = [ craneLib.cargo ] ++ packages;
      inherit inputsFrom env;
      shellHook = lib.optionalString (pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform) ''
        if [ -t 1 ]; then
          _bold=$'\e[1m' _blue=$'\e[34m' _reset=$'\e[0m'
        else
          _bold="" _blue="" _reset=""
        fi
        echo "''${_bold}Entering cross compilation environment...''${_reset}"
        echo "  - GCC: ''${_blue}$(${selectedStdenv.cc.targetPrefix}cc --version | head -n1)''${_reset}"
        echo "  - Rust: ''${_blue}$(rustc --version)''${_reset}"
        echo "  - CARGO_BUILD_TARGET: ''${_blue}$CARGO_BUILD_TARGET''${_reset}"
        echo "  - CARGO_PROFILE: ''${_blue}$CARGO_PROFILE''${_reset}"
      '' + shellHook;
    });

  shell = mkShell { };

  workspaceCommonArgs = {
    # # TODO: clean source, but include assets
    # src = craneLib.cleanCargoSource workspace.src;
    inherit cargoVendorDir;
    src = workspace.src;
    pname = "workspace";
    cargoArtifacts = commonCargoArtifacts;
    doInstallCargoArtifacts = false;
    postUnpack = workspacePostUnpack;
  } // crateEnv;

  workspaceArg = "--workspace" + (if workspace.disableKeepGoing then "" else " --keep-going");

  # derivation that runs `cargo build` on the entire workspace
  build = craneLib.cargoBuild (commonArgs // workspaceCommonArgs // {
    version = "0.0.0";
    cargoExtraArgs = lib.strings.trim "${workspaceArg} ${featuresArgs}";
    fixupPhase = ":";
    doCheck = false;
  });

  # derivation that runs `cargo clippy` on the entire workspace
  clippy = craneLib.cargoClippy (commonArgs // workspaceCommonArgs // {
    version = "0.0.0";
    cargoExtraArgs = lib.strings.trim "${workspaceArg} ${featuresArgs}";
    cargoClippyExtraArgs = "--all-targets -- -D warnings";
    fixupPhase = ":";
    doCheck = false;
  });

  # derivation that runs `cargo doc` scoped to either the whole workspace
  # (the default) or a specific `-p <pkg>` selector. `extraArgs` is appended
  # to the rustdoc invocation, e.g. `--document-private-items`.
  mkCargoDoc =
    { package ? null
    , extraArgs ? ""
    }:
    let
      scopeArg =
        if package == null
        then workspaceArg
        else "--package ${package}";
    in
    craneLib.cargoDoc (commonArgs // workspaceCommonArgs // {
      version = "0.0.0";
      cargoExtraArgs = lib.strings.trim "${scopeArg} ${featuresArgs}";
      cargoDocExtraArgs = lib.strings.trim "--no-deps ${extraArgs}";
      RUSTDOCFLAGS = "-D warnings";
      fixupPhase = ":";
      doCheck = false;
    });

  # derivation that runs `cargo test` on the entire workspace
  test = craneLib.cargoTest (commonArgs // workspaceCommonArgs // {
    version = "0.0.0";
    cargoExtraArgs = lib.strings.trim "--workspace ${featuresArgs}";
    fixupPhase = ":";
    doCheck = true;
  });

  # derivation that runs `cargo nextest run` on the entire workspace
  nextest = craneLib.cargoNextest (commonArgs // workspaceCommonArgs // {
    version = "0.0.0";
    cargoNextestExtraArgs = lib.strings.trim "--workspace --hide-progress-bar ${featuresArgs}";
    fixupPhase = ":";
    doCheck = true;
  });

  # derivation that runs `cargo deny check` on the entire workspace
  mkCargoDeny =
    { config ? false
    , checks ? [ "bans" "licenses" "sources" ]
    }: craneLib.cargoDeny (commonArgs // workspaceCommonArgs // {
      version = "0.0.0";
      cargoExtraArgs = if config != false then "--config ${config}" else "";
      cargoDenyChecks = if builtins.isList checks then builtins.concatStringsSep " " checks else checks;
      fixupPhase = ":";
      doCheck = true;
    });
in
{
  stdenv = selectedStdenv;
  deps = commonCargoArtifacts;
  inherit mkShell shell;
  inherit build clippy test nextest mkCargoDeny mkCargoDoc;
  inherit pkgs;
  buildCrate = import ./buildCrate.nix inputs workspace {
    inherit pkgs craneLib rustProfile minimalDeps denix upx env crateEnv nativeDeps targetDeps runtimeDeps runtimeEnv wrapNixGL;
    inherit commonArgs commonCargoArtifacts cargoVendorDir dummySrc;
    inherit includeExtraSrc workspacePostUnpack localDepClosure;
  };
}
