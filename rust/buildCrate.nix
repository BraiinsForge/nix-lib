# inherited args
inputs: workspace: profile:
# this fn's args
crate_def: { minimal_deps ? profile.minimal_deps
           , denix ? profile.denix
           , upx ? profile.upx
           , env ? { }
           , features ? [ ]
           , noDefaultFeatures ? false
           }:
let crate = { inherit minimal_deps denix upx env features noDefaultFeatures; }; in
let
  pkgs = inputs.pkgs;
  lib = inputs.pkgs.lib;
  craneLib = inputs.craneLib;
  nix-filter = inputs.nix-filter;
  docker-spider = inputs.docker-spider;
  localSystem = inputs.localSystem;
  commonArgs = profile.commonArgs;
in
with builtins;
let
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
    buildPhaseCargoCommand = lib.concatStringsSep " " [
      "cargoWithProfile build"
      # this is not a mistake, `packageName` is actually needed for `--bin`
      "--bin crane-dummy-${crate_def.packageName}"
      (if crate.minimal_deps then "--package ${crate_def.packageName}" else "")
      featuresArgs
    ];
    cargoArtifacts = profile.commonCargoArtifacts;
    pname = "${crate_def.binName}" + profile.suffix;
    pnameSuffix = "-ext";
    version = "0.0.0";
    doInstallCargoArtifacts = true;
    src = craneLib.mkDummySrc { src = workspace.manifests_src; };
    doCheck = false;
  });

  # crate path relative to the workspace root
  relativeCratePath = lib.path.removePrefix workspace.src crate_def.path;

  # crate path within cargo manifest derivation
  manifestCratePath = "${workspace.manifestSearch}/${relativeCratePath}";

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
  calculateSrc = pkgs.runCommand "${crate_def.binName}-srcpaths" { } ''
    cd ${manifestCratePath}
    mkdir $out
    gen_sources () {
        set -x
        curr_dir="$(pwd)"
        crate_dir="$(dirname $1)/"
        echo "{ me = \"$crate_dir\"; srcs = [" >> $out/paths.tmp
        ${docker-spider.outputs.packages.${localSystem}.default}/bin/docker-spider p --list $1 2>/dev/null | awk -- '{print "\"" $0 "\"";}' >> $out/paths.tmp
        echo "\"$crate_dir\"" >> $out/paths.tmp
        echo "]; }" >> $out/paths.tmp
        to_replace="$(echo $(pwd) | grep -Eo '/nix/store/[A-Za-z0-9_-]+/')"
        sed -i "s|$to_replace||g" $out/paths.tmp
        self=$(echo $(pwd) | sed  "s|$to_replace||")
        sed -i "s|\./|$self|" $out/paths.tmp
        cat $out/paths.tmp > $out/paths.nix
        rm $out/paths.tmp
        set +x
    }
    gen_sources ./Cargo.toml
  '';
  final_src = import "${calculateSrc}/paths.nix";

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
    pname = crate_def.binName + profile.suffix;
    doInstallCargoArtifacts = false;
    cargoToml = crate_def.path + /Cargo.toml;
    cargoLock = workspace.src + /Cargo.lock;
    src = nix-filter.lib.filter {
      root = workspace.src;
      include = final_src.srcs ++ [
        (workspace.src + /.cargo)
        (workspace.src + /Cargo.toml)
        (workspace.src + /Cargo.lock)
      ];
    };
    preBuild = ''
      mkdir -p target
      cp -r --no-clobber ${workspace.manifestSearch}/* . 2>/dev/null || true
    '';
    cargoArtifacts = if !(profile.build_pkgs.stdenv.hostPlatform.isWindows || profile.build_pkgs.stdenv.hostPlatform.isDarwin) then cargoArtifacts else trace "windows and mac suck, not including prebuilt deps in windows builds" null;
    # ↑ capctl makes me sad :( it is not smart enough to not compile in any Linux-only stuff on windows,
    # and so we cannot compile all deps
  };


  doUpx = crate.upx != "none";
  upxArgs = {
    none = "";
    default = "";
    lzma = "--lzma";
  }.${crate.upx};


  wasmBindgenCliExtension = if workspace.wasm-bindgen-cli != null then { wasm-bindgen-cli = workspace.wasm-bindgen-cli; } else { };


  package = {
    bin = craneLib.buildPackage (commonArgs // packageCommonArgs // {
      cargoExtraArgs = lib.concatStringsSep " " [
        "--bin ${crate_def.binName}"
        (if crate.minimal_deps then "--package ${crate_def.packageName}" else "")
        featuresArgs
      ];
      doCheck = false;
      postInstall = lib.optionalString workspace.addSuffixToBinaries ''
        for file in $out/bin/*; do
          mv -v --no-clobber "$file" "''${file}${profile.suffix}" || true
        done
      '' + lib.optionalString crate.denix ''
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
        ${pkgs.upx}/bin/upx ${upxArgs} $out/bin/*
      '';
    });
    trunk = craneLib.buildTrunkPackage (commonArgs // packageCommonArgs // wasmBindgenCliExtension // {
      cargoArtifacts = null;

      # we're overriding filtered src from `packageCommonArgs`, because `trunk` calls `cargo metadata`, and it breaks because of the incomplete workspace...
      src = workspace.src;

      preBuild = ''
        # trunk can't find `index.html` unless we're in the crate directory
        cd ${relativeCratePath}
      '';
      cargoExtraArgs = lib.concatStringsSep " " [
        "--bin ${crate_def.binName}"
        (if crate.minimal_deps then "--package ${crate_def.packageName}" else "")
        featuresArgs
      ];
      doCheck = false;
    });
    # parts of this are copied from https://github.com/ipetkov/crane/pull/358/files#diff-927c8ebbb8df8910593fa69522426d29fea7e7009950b66594278fd9e9aa5e92
    tauri = craneLib.mkCargoDerivation (commonArgs // packageCommonArgs // {
      cargoArtifacts = null;

      nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [
        craneLib.installFromCargoBuildLogHook
        pkgs.cargo-tauri
        pkgs.jq
        pkgs.fd
      ];

      buildPhaseCargoCommand = ''
        cargoBuildLog=$(realpath $(mktemp cargoBuildLogXXXX.json))

        # tauri fails to find the built binary without this
        local targetArg
        if [[ -n "$CARGO_BUILD_TARGET" ]]; then
          targetArg="--target $CARGO_BUILD_TARGET"
        fi

        # cd-ing into the crate directory because `cargo tauri build` does not support `-p`
        pushd ${relativeCratePath}

        # extra config is merged with `tauri.conf.json` in the source tree
        cargo tauri build $targetArg --ci --config ${pkgs.writeText "tauri.conf.json" (builtins.toJSON crate_def.extraTauriConf)} -- --message-format json-render-diagnostics >"$cargoBuildLog"

        popd
      '';
      installPhaseCommand = ''
        if [ -n "$cargoBuildLog" -a -f "$cargoBuildLog" ]; then
          installFromCargoBuildLog "$out" "$cargoBuildLog"
        else
          echo ${lib.strings.escapeShellArg ''
            !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            $cargoBuildLog is either undefined or does not point to a valid file location!
            By default `buildPackage` will capture cargo's output and use it to determine which binaries
            should be installed (instead of just guessing based on what is present in cargo's target directory).
            If you are overriding the derivation with a custom build step, you have two options:
            1. override `installPhaseCommand` with the appropriate installation steps
            2. ensure that cargo's build log is captured in a file and point $cargoBuildLog at it
            At a minimum, the latter option can be achieved with running:
                cargoBuildLog=$(mktemp cargoBuildLogXXXX.json)
                cargo build --release --message-format json-render-diagnostics >"$cargoBuildLog"
          ''}

          false
        fi
      '' + ''
        mkdir -p $out
        fd '.*' target/ --extension deb --exec cp {} -t $out
      '';
      doCheck = false;
    });
  };

in
package.${crate_def.type}
