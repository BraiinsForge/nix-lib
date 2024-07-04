pkgs:
let lib = pkgs.lib; in
{

  # tiny helper function to convert a derivation to a flake app
  mkApp = drv: { type = "app"; program = lib.getExe drv; };

  # usage: `out = strftime 1706207938 "%Y-%m-%d_%H-%M-%S";`
  strftime = ts: fmt:
    builtins.readFile (pkgs.runCommand "strftime" { } ''echo -n $(date -d @"${builtins.toString ts}" +"${fmt}") > $out'');

  # usage: `readYaml ./path/to/file.yml`
  readYaml = path:
    let
      jsonOutputDrv = pkgs.runCommand "yaml2json" { } ''
        ${pkgs.remarshal}/bin/remarshal -if yaml -i "${path}" -of json -o "$out"
      '';
    in
    builtins.fromJSON (builtins.readFile jsonOutputDrv);

  # map names of attributes in an attribute set
  mapAttrNames = f: set: lib.mapAttrs' (name: value: { name = f name; inherit value; }) set;

  # map values of attributes in an attribute set
  mapAttrValues = f: set: lib.mapAttrs' (name: value: { inherit name; value = f value; }) set;

  # write a shell application with a clean env
  writeCleanEnvShellApp = name: deps: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = deps;
    runtimeEnv.PATH = null;
    excludeShellChecks = [ "SC2123" ];
  };

}
