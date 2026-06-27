# inherited args
inputs: workspace: profile:
# this fn's args
crate_def: { minimalDeps ? profile.minimalDeps
           , denix ? profile.denix
           , upx ? profile.upx
           , env ? { }
           , features ? [ ]
           , noDefaultFeatures ? false
           , runtimeDeps ? profile.runtimeDeps
           , runtimeEnv ? profile.runtimeEnv
           , wrapNixGL ? profile.wrapNixGL
           }:
let
  crate = { inherit minimalDeps denix upx env features noDefaultFeatures; };
  pkgs = profile.pkgs;
  lib = pkgs.lib;
  fs = lib.fileset;
  craneLib = profile.craneLib;
  commonArgs = profile.commonArgs;

  workspacePath = workspace.workspacePath;
  workspacePrefix = lib.optionalString (workspacePath != "") "${workspacePath}/";
  # Relative path from the workspace root back to the source root,
  # e.g. "examples" -> "..", "a/b" -> "../..", "" -> "."
  srcRootFromWorkspace =
    if workspacePath == "" then "."
    else lib.concatStringsSep "/" (map (_: "..") (lib.splitString "/" workspacePath));

  # When binName is false (e.g. cdylib crates), use packageName for
  # derivation naming and omit --bin from cargo commands.
  hasBinTarget = crate_def.binName != false;
  effectiveName = if hasBinTarget then crate_def.binName else crate_def.packageName;
  binArg = if hasBinTarget then "--bin ${crate_def.binName}" else "--package ${crate_def.packageName}";
in
let
  finalRuntimeDeps =
    if builtins.isFunction runtimeDeps then runtimeDeps pkgs
    else runtimeDeps;
  finalRuntimeEnv =
    if builtins.isFunction runtimeEnv then runtimeEnv pkgs
    else runtimeEnv;

  featuresArgs =
    let
      noDefaultFeaturesArg = if crate.noDefaultFeatures then "--no-default-features" else "";
      commaSeparatedFeatures = lib.concatStringsSep "," crate.features;
      featuresArg = if crate.features == [ ] then "" else "--features " + commaSeparatedFeatures;
    in
    lib.concatStringsSep " " [ noDefaultFeaturesArg featuresArg ];

  # NOTE: `package` and `bin` modes behave differently: https://github.com/rust-lang/cargo/issues/8157
  #   - `--bin` implies `--workspace` and includes union of cargo features from all workspace crates (binaries are larger)
  #   - `--package` causes rebuilds of some dependencies, because `cargo build` in previous step uses `--workspace`

  # extend common artifacts with additional artifacts needed just for the current package
  cargoArtifacts = craneLib.mkCargoDerivation (commonArgs // {
    inherit (profile) cargoVendorDir;
    buildPhaseCargoCommand = lib.concatStringsSep " " [
      "cargoWithProfile build"
      binArg
      (if hasBinTarget && crate.minimalDeps then "--package ${crate_def.packageName}" else "")
      featuresArgs
      profile.timingsArg
    ];
    cargoArtifacts = profile.commonCargoArtifacts;
    pname = effectiveName;
    pnameSuffix = "-ext";
    version = "0.0.0";
    doInstallCargoArtifacts = true;
    src = profile.dummySrc;
    postUnpack = profile.workspacePostUnpack;
    doCheck = false;
  });

  # crane-default filter (rust/toml/lock) + each crate's `[package.metadata.nix].include`,
  # over this crate's local-dep closure. The fileset is built in the profile so the
  # workspace-level derivations (build/clippy/test) share the exact same per-crate logic.
  crateFileset = profile.mkCrateFileset {
    dirs = profile.localDepClosure crate_def.relativePath;
  };
  filteredSrc = fs.toSource {
    root = workspace.src;
    fileset = crateFileset;
  };

  #######################################################################
  # this is essentially the old bos-main CI mechanism, but better, and
  # without having to use docker and a ton of auxiliary tools to do it:
  # - steal Cargo.lock from root (it is compatible)
  # - take Cargo.toml for the particular crate
  # - orchestrate local deps, wilfully forgetting any notion of a workspace
  #
  # It is also way faster
  #
  # Crates don't care about being in a workspace unless you use workspace
  # downstream dependencies, which pls don't use or I will have a stroke.
  #
  # This means that we can creatively make subsets of the source files to
  # only limit to what a particular crate needs to build, which should
  # make it more cache sensible.
  ########################################################################
  packageCommonArgs = profile.crateEnv // crate_def.env // crate.env // {
    inherit (profile) cargoVendorDir;
    pname = effectiveName;
    doInstallCargoArtifacts = false;
    cargoToml = "${profile.dummySrc}/${workspacePrefix}${crate_def.relativePath}/Cargo.toml";
    cargoLock = "${profile.dummySrc}/${workspacePrefix}Cargo.lock";
    src = filteredSrc;
    postUnpack = profile.workspacePostUnpack;
    # re-add, as stubs, the unrelated crates filtered out of filteredSrc, otherwise cargo fails
    preBuild = ''
      mkdir -p target
      cp -r --no-clobber ${profile.dummySrc}/* ${srcRootFromWorkspace}/ 2>/dev/null || true
    '';
    inherit cargoArtifacts;
    # the resolved source file list, attached for debugging: nix eval --json .#<drv>.passthru.srcFiles
    passthru.srcFiles = profile.srcFileList crateFileset;
  };


  doUpx = crate.upx != "none";
  upxArgs = {
    none = "";
    default = "";
    lzma = "--lzma";
  }.${crate.upx};


  package = {
    bin = workspace.patchSourceInfo (craneLib.buildPackage (commonArgs // packageCommonArgs // {
      cargoExtraArgs = lib.concatStringsSep " " [
        binArg
        (if hasBinTarget && crate.minimalDeps then "--package ${crate_def.packageName}" else "")
        featuresArgs
        profile.timingsArg
      ];
      doCheck = false;
      # strip is controlled directly by cargo profile
      dontStrip = true;
      postInstall = lib.optionalString crate.denix ''
        for file in $out/bin/*; do
          echo "denixing $file"
          interpreter=$(patchelf --print-interpreter "$file" | sed -r 's#^/nix/store/[^/]*(/.*)$#\1#;t;d')

          # rewrite lib to lib64 for x86_64 builds
          if [ "$interpreter" == "/lib/ld-linux-x86-64.so.2" ]; then
            interpreter="/lib64/ld-linux-x86-64.so.2"
          fi

          echo "setting interpreter to '$interpreter'"
          patchelf --remove-rpath --set-interpreter "$interpreter" "$file"
        done
      '' + lib.optionalString doUpx ''
        ${pkgs.pkgsBuildBuild.upx}/bin/upx ${upxArgs} $out/bin/*
      '' + lib.optionalString (finalRuntimeDeps != [ ] || finalRuntimeEnv != { } || wrapNixGL) (
        let
          wrapper = import ../wrapper.nix ({
            inherit wrapNixGL lib;
            runtimeDeps = finalRuntimeDeps;
            runtimeEnv = finalRuntimeEnv;
            inherit (pkgs) runtimeShell;
            inherit (pkgs) runCommand;
          } // (if wrapNixGL then {
            inherit (pkgs) mesa libglvnd;
          } else { }));
        in
        ''
          cp $out/bin/${crate_def.binName} $out/bin/.${crate_def.binName}-wrapped
          echo "${wrapper}" > $out/bin/${crate_def.binName}
          echo "exec $out/bin/.${crate_def.binName}-wrapped" >> $out/bin/${crate_def.binName}
          chmod +x $out/bin/${crate_def.binName}
        ''
      );
    }));
    trunk = throw "trunk crate support has been removed as it was unused";
    tauri = throw "tauri crate support has been removed as it was unused";
  };

in
package.${crate_def.type}
