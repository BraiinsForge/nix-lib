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
, timings ? workspace.timings
}:
assert !allFeatures || (features == [ ] && !noDefaultFeatures); # `allFeatures` is mutually exclusive with explicit feature selection
let lib = pkgs.lib; in
let pkgs' = pkgs; in
let pkgs = (pkgs'.extend inputs.fenix.overlays.default); in
let
  fs = lib.fileset;
  globset = inputs.globset.lib;

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

  timingsArg = lib.optionalString timings "--timings";

  preserveTimings = nameSuffix: ''
    targetDir="''${CARGO_TARGET_DIR:-target}"
    if test -f "$targetDir/cargo-timings/cargo-timing.html"; then
      mkdir -p "$targetDir/nix-cargo-timings"
      mv "$targetDir/cargo-timings/cargo-timing.html" "$targetDir/nix-cargo-timings/cargo-timing-$pname${nameSuffix}.html"
    fi
  '';

  # set of arguments that must be the same for `buildDepsOnly` and `buildPackage`, to prevent full workspace rebuilds in `buildPackage`
  commonArgs =
    {
      nativeBuildInputs = (workspace.nativeDeps pkgs.pkgsBuildBuild) ++ (nativeDeps pkgs.pkgsBuildBuild);
      buildInputs = (workspace.targetDeps pkgs) ++ (targetDeps pkgs) ++ (lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ]);
      CARGO_PROFILE = rustProfile;
      strictDeps = true;
      CARGO_INCREMENTAL = "0"; # incremental compilation is always counterproductive in sandbox
      postPhases = lib.optional timings "timingsInstallPhase" ++ lib.optional sccache "sccacheStatsPhase";
    }
    // workspace.env
    // env
    // lib.optionalAttrs (rustCrossTargetOverride != null) { CARGO_BUILD_TARGET = rustCrossTargetOverride; }
    // lib.optionalAttrs timings {
      preInstallPhases = [ "timingsPreservePhase" ];
      timingsPreservePhase = preserveTimings "";
      timingsInstallPhase = ''
        chartsDir="''${CARGO_TARGET_DIR:-target}/nix-cargo-timings"
        if test "''${doInstallCargoArtifacts:-}" != 1 && test -d "$chartsDir"; then
          cp -r "$chartsDir" "$out/cargo-timings"
        fi
      '';
    }
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

  # `cargo metadata` extracted from the crane dummy src
  cargoMetadata = builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile (pkgs.runCommand "cargo-metadata.json"
    { nativeBuildInputs = [ craneLib.cargo ]; }
    ''
      export CARGO_HOME="$(mktemp -d)"
      cd ${dummySrc}/${workspacePrefix}
      cargo metadata --no-deps --format-version 1 --offline >"$out"
    '')));

  # crate dir (relative to the cargo workspace root) -> its direct local path-dep dirs
  metaRel = abs: lib.removePrefix "/" (lib.removePrefix cargoMetadata.workspace_root abs);
  localDepEdges = lib.listToAttrs (map
    (pkg: {
      name = metaRel (dirOf pkg.manifest_path);
      value = map (d: metaRel d.path) (builtins.filter (d: (d.path or null) != null) pkg.dependencies);
    })
    cargoMetadata.packages);

  # all workspace members (dirs relative to the cargo workspace root)
  workspaceMemberDirs = builtins.attrNames localDepEdges;

  # transitive closure of local path-deps for a crate dir, including the crate itself
  localDepClosure =
    let
      visit = acc: cur:
        if builtins.elem cur acc then acc
        else builtins.foldl' visit (acc ++ [ cur ]) (localDepEdges.${cur} or [ ]);
    in
    dir: visit [ ] dir;

  # absolute path of the cargo workspace root within the source tree
  workspaceRootPath = workspace.src + (lib.optionalString (workspacePath != "") "/${workspacePath}");

  # absolute path of a crate dir (relative to the cargo workspace root) within the source tree
  crateDir = relDir: workspaceRootPath + "/${relDir}";

  # extra files a crate opts into via `[package.metadata.nix] include = [ ... ]`
  crateIncludeFileset = relDir:
    let manifest = fromTOML (builtins.readFile (crateDir relDir + "/Cargo.toml"));
    in globset.globs (crateDir relDir)
      (map builtins.unsafeDiscardStringContext (manifest.package.metadata.nix.include or [ ]));

  # fileset for one crate: crane's default rust/toml/lock filter + its declared `include` globs
  crateFileset = relDir:
    fs.unions [
      (craneLib.fileset.commonCargoSources (crateDir relDir))
      (crateIncludeFileset relDir)
    ];

  # profile-level `includeExtraSrc` paths, verbatim, each tolerant of being absent
  extraSrc = map (p: fs.maybeMissing (workspace.src + "/${p}"));

  # Fileset for a crate + its local-dep closure: each crate's fileset, plus the workspace
  # cargo manifests, the root cargo config, and the profile-level `includeExtraSrc`.
  mkCrateFileset = { dirs, includeExtraSrc }:
    fs.unions (
      (map crateFileset dirs)
      ++ [
        (fs.maybeMissing (workspaceRootPath + "/.cargo/config.toml"))
        (fs.maybeMissing (workspaceRootPath + "/Cargo.toml"))
        (fs.maybeMissing (workspaceRootPath + "/Cargo.lock"))
      ]
      ++ extraSrc includeExtraSrc
    );

  # fileset for whole-workspace derivations
  workspaceFileset = fs.unions (
    [ (craneLib.fileset.commonCargoSources workspaceRootPath) ]
    ++ map crateIncludeFileset workspaceMemberDirs
    ++ extraSrc includeExtraSrc
  );

  # the exact file list a fileset resolves to, as paths relative to the source root
  srcFileList = fileset:
    map (p: lib.removePrefix "${toString workspace.src}/" (toString p)) (fs.toList fileset);

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
  depsCargoExtraArgs = lib.strings.trim "--locked --all-targets ${featuresArgs}";
  commonCargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
    inherit cargoVendorDir;
    inherit dummySrc;
    pname = "workspace";
    version = "0.0.0";
    cargoExtraArgs = depsCargoExtraArgs;
    doCheck = false;
    postUnpack = workspacePostUnpack;
  } // lib.optionalAttrs timings {
    # replicates crane's default `cargo check` + `cargo build` sequence, preserving
    # timing in between so the check pass gets its own timing chart instead
    # of being overwritten by the build pass
    buildPhaseCargoCommand = ''
      cargoWithProfile check ${depsCargoExtraArgs} ${timingsArg}
      ${preserveTimings "-check"}
      cargoWithProfile build ${depsCargoExtraArgs} ${timingsArg}
    '';
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
    inherit cargoVendorDir;
    src = fs.toSource {
      root = workspace.src;
      fileset = workspaceFileset;
    };
    pname = "workspace";
    cargoArtifacts = commonCargoArtifacts;
    doInstallCargoArtifacts = false;
    postUnpack = workspacePostUnpack;
    # the resolved source file list, attached for debugging: nix eval --json .#<drv>.passthru.srcFiles
    passthru.srcFiles = srcFileList workspaceFileset;
  } // crateEnv;

  workspaceArg = "--workspace" + (if workspace.disableKeepGoing then "" else " --keep-going");

  # derivation that runs `cargo build` on the entire workspace
  build = craneLib.cargoBuild (commonArgs // workspaceCommonArgs // {
    version = "0.0.0";
    cargoExtraArgs = lib.strings.trim "${workspaceArg} ${featuresArgs} ${timingsArg}";
    fixupPhase = ":";
    doCheck = false;
  });

  # derivation that runs `cargo clippy` on the entire workspace
  clippy = craneLib.cargoClippy (commonArgs // workspaceCommonArgs // {
    version = "0.0.0";
    cargoExtraArgs = lib.strings.trim "${workspaceArg} ${featuresArgs} ${timingsArg}";
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
      cargoExtraArgs = lib.strings.trim "${scopeArg} ${featuresArgs} ${timingsArg}";
      cargoDocExtraArgs = lib.strings.trim "--no-deps ${extraArgs}";
      RUSTDOCFLAGS = "-D warnings";
      fixupPhase = ":";
      doCheck = false;
    });

  # derivation that runs `cargo test` on the entire workspace
  test = craneLib.cargoTest (commonArgs // workspaceCommonArgs // {
    version = "0.0.0";
    cargoExtraArgs = lib.strings.trim "--workspace ${featuresArgs} ${timingsArg}";
    fixupPhase = ":";
    doCheck = true;
  });

  # derivation that runs `cargo nextest run` on the entire workspace
  nextest = craneLib.cargoNextest (commonArgs // workspaceCommonArgs // {
    version = "0.0.0";
    cargoExtraArgs = timingsArg;
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
    inherit includeExtraSrc workspacePostUnpack localDepClosure mkCrateFileset srcFileList timingsArg;
  };
}
