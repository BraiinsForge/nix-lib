# inherited args
inputs: workspace: profile:
# this fn's args
crate_def: { minimal_deps ? profile.minimal_deps, upx ? profile.upx, env ? { }, features ? [ ], noDefaultFeatures ? false }:
let crate = { inherit minimal_deps upx env features noDefaultFeatures; }; in
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
      # this is not a mistake, `package_name` is actually needed for `--bin`
      "--bin crane-dummy-${crate_def.package_name}"
      (if crate.minimal_deps then "--package ${crate_def.package_name}" else "")
      featuresArgs
    ];
    cargoArtifacts = profile.commonCargoArtifacts;
    pname = "${crate_def.bin_name}" + profile.suffix;
    pnameSuffix = "-ext";
    version = "0.0.0";
    doInstallCargoArtifacts = true;
    src = craneLib.mkDummySrc { src = workspace.manifests_src; };
    doCheck = false;
  });

  ##########################################################################
  # We are dissecting an in-repo path from a nix store path for the package
  # so that we know in which folder to run docker-spider to get paths for
  # this particular crate
  ##########################################################################
  target_path =
    let
      stringified = toString crate_def.src_path; # path -> string
      splittified = builtins.split "/" stringified; # split into path segments
      droppified = lib.drop 8 splittified; # drop the /nix/store/.... prefix
      filtered = filter (x: (typeOf x) == "string") droppified; # remove sub-lists representing holes left after delimiters
      concatted = lib.concatStringsSep "/" filtered; # rejoin into a stringly path
    in
    # produce local path within cargo manifest derivation
    toString "${workspace.manifestSearch}/${concatted}";

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
  calculateSrc = pkgs.runCommand "${crate_def.bin_name}-srcpaths" { } ''
    cd ${target_path}
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
  final_src = (import "${calculateSrc}/paths.nix");

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
  packageCommonArgs = crate_def.env // crate.env // {
    pname = crate_def.bin_name + profile.suffix;
    doInstallCargoArtifacts = false;
    cargoToml = crate_def.src_path + /Cargo.toml;
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
      cp -r --no-clobber ${workspace.manifestSearch}/* . || true
    '';
    cargoArtifacts = if !(profile.build_pkgs.stdenv.hostPlatform.isWindows || profile.build_pkgs.stdenv.hostPlatform.isDarwin) then cargoArtifacts else trace "windows and mac suck, not including prebuilt deps in windows builds" null;
    # ↑ capctl makes me sad :( it is not smart enough to not compile in any Linux-only stuff on windows,
    # and so we cannot compile all deps
  };

  package =
    let
      doUpx = crate.upx != "none";
      upxArgs = {
        none = "";
        default = "";
        lzma = "--lzma";
      }.${crate.upx};
    in
    craneLib.buildPackage (commonArgs // packageCommonArgs // {
      cargoExtraArgs = lib.concatStringsSep " " [
        "--bin ${crate_def.bin_name}"
        (if crate.minimal_deps then "--package ${crate_def.package_name}" else "")
        featuresArgs
      ];
      doCheck = false;
      postInstall = lib.optionalString workspace.addSuffixToBinaries ''
        for file in $out/bin/*; do
          mv -v --no-clobber "$file" "''${file}${profile.suffix}" || true
        done
      '' + lib.optionalString doUpx ''
        ${pkgs.upx}/bin/upx ${upxArgs} $out/bin/*
      '';
    });

in
package
