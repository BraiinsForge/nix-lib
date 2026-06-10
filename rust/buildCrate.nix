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
           , includeExtraSrc ? profile.includeExtraSrc
           }:
let
  crate = { inherit minimalDeps denix upx env features noDefaultFeatures; };
  pkgs = profile.pkgs;
  lib = pkgs.lib;
  craneLib = profile.craneLib;
  nix-filter = inputs.nix-filter;
  docker-spider = inputs.docker-spider;
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

  # crate path within cargo manifest derivation
  manifestCratePath = "${workspace.manifestSearch}/${workspacePrefix}${crate_def.relativePath}";

  #######################################################################
  # docker-spider is not dead, it's now a nix util :D
  #
  # In this script, we take the previously generated manifest derivation
  # and we use docker-spider to calculate the sources for this particular
  # crate.
  #
  # This will produce a `paths.nix` file, which looks like this:
  #
  # ```nix
  # {
  #    me = "path/to/this/crate/from/repo/root";
  #    srcs = [
  #    "list"
  #    "of"
  #    "relevant"
  #    "folders"
  #    ];
  # }
  # ```
  #
  # The list also contains self directory stupidly as `./`, so the bash
  # script that formats docker-spider output into nix fixes this.
  #######################################################################
  calculateSrc = pkgs.runCommand "${effectiveName}-srcpaths" { } ''
    cd ${manifestCratePath}
    mkdir $out
    gen_sources () {
        curr_dir="$(pwd)"
        crate_dir="$(dirname $1)/"
        echo "{ me = \"$crate_dir\"; srcs = [" >> $out/paths.tmp
        ${docker-spider.outputs.packages.${pkgs.stdenv.buildPlatform.system}.default}/bin/docker-spider p --list $1 | awk -- '{print "\"" $0 "\"";}' >> $out/paths.tmp
        echo "\"$crate_dir\"" >> $out/paths.tmp
        echo "]; }" >> $out/paths.tmp
        to_replace="$(echo $(pwd) | grep -Eo '/nix/store/[A-Za-z0-9_-]+/')"
        sed -i "s|$to_replace||g" $out/paths.tmp
        self=$(echo $(pwd) | sed  "s|$to_replace||")
        sed -i "s|\./|$self|" $out/paths.tmp
        cat $out/paths.tmp > $out/paths.nix
        rm $out/paths.tmp
        cat $out/paths.nix | ${pkgs.pkgsBuildBuild.nixpkgs-fmt}/bin/nixpkgs-fmt
    }
    gen_sources ./Cargo.toml
  '';
  finalSrc = import "${calculateSrc}/paths.nix";

  cargoFiles = [ "${workspacePrefix}Cargo.toml" "${workspacePrefix}Cargo.lock" ];

  filteredSrc = nix-filter.lib.filter {
    root = workspace.src;
    include = finalSrc.srcs ++ [ ".cargo" ] ++ cargoFiles ++ includeExtraSrc;
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
    preBuild = ''
      mkdir -p target
      cp -r --no-clobber ${workspace.manifestSearch}/* ${srcRootFromWorkspace}/ 2>/dev/null || true
    '';
    inherit cargoArtifacts;
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
