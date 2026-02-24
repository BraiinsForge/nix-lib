pkgs:
let lib = pkgs.lib; in
{

  # tiny helper function to convert a derivation to a flake app
  mkApp = drv: { type = "app"; program = lib.getExe drv; };

  # usage: `out = strftime 1706207938 "%Y-%m-%d_%H-%M-%S";`
  strftime = ts: fmt:
    builtins.readFile (pkgs.runCommand "strftime" { } ''echo -n $(date -d @"${toString ts}" +"${fmt}") > $out'');

  # usage: `readYaml ./path/to/file.yml`
  readYaml = file:
    let
      jsonOutputDrv = pkgs.runCommand "yaml2json" { } ''
        ${pkgs.remarshal}/bin/remarshal -if yaml -i "${file}" -of json -o "$out"
      '';
    in
    builtins.fromJSON (builtins.readFile jsonOutputDrv);

  # usage: `readJson5 ./path/to/file.json5`
  readJson5 = file:
    let
      jsonOutputDrv = pkgs.runCommand "json52json" { } ''
        ${pkgs.python3Packages.json5}/bin/pyjson5 --as-json "${file}" > "$out"
      '';
    in
    builtins.fromJSON (builtins.readFile jsonOutputDrv);

  # map names of attributes in an attribute set
  mapAttrNames = f: set: lib.mapAttrs' (name: value: { name = f name; inherit value; }) set;

  # map values of attributes in an attribute set
  mapAttrValues = f: set: lib.mapAttrs' (name: value: { inherit name; value = f value; }) set;

  # write a shell application with a clean env
  writeCleanEnvShellApp = { name, text, deps ? [ ], env ? { }, excludeShellChecks ? [ ], meta ? { } }: pkgs.writeShellApplication {
    inherit name text meta;
    runtimeInputs = deps;
    runtimeEnv = env // { PATH = null; };
    excludeShellChecks = excludeShellChecks ++ [ "SC2123" ];
  };

  # wrapper around `pkgs.dockerTools.buildImage`
  mkDockerImage = { name, tag, crate, arch ? null, binaryName ? "", extraBuildParams ? { } }:
    let
      baseArgs = {
        inherit name tag;

        created = "now";
        copyToRoot = with pkgs; [ crate bash coreutils-full ];

        config = {
          Entrypoint = [ "${crate}/bin/${if binaryName == "" then name else binaryName}" ];
        };

        architecture = arch;
      };
      args = lib.recursiveUpdate baseArgs extraBuildParams;
    in
    pkgs.dockerTools.buildImage args;

  # build a docker manifest out of individual images
  mkDockerManifest = { images }:
    let
      docker = "${pkgs.docker}/bin/docker";

      imageTag = image: "$TAG-${image.arch}-${image.os}";
      loadAndPush = images: builtins.concatStringsSep "\n" (map
        (image: ''
          IMAGE=$(${docker} load -i ${image.image} | tail -n1 | cut -d' ' -f3)
          ${docker} tag "$IMAGE" "${imageTag image}"
          ${docker} push "${imageTag image}"
        '')
        images);
      amendImages = images: builtins.concatStringsSep " " (map
        (image: ''--amend "${imageTag image}"'')
        images);
    in
    pkgs.writeShellScriptBin "docker-manifest" ''
      set -e

      TAG=$1
      [[ -z "$TAG" ]] && echo "Manifest image tag not provided" >&2 && exit 1

      set -x # echo on

      set +e
      ${docker} manifest rm "$TAG"
      set -e

      ${loadAndPush images}

      ${docker} manifest create "$TAG" ${amendImages images}
      ${docker} manifest push --purge "$TAG"
    '';

}
