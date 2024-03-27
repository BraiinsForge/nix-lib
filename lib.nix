pkgs: {

  # tiny helper function to convert a derivation to a flake app
  mkApp = drv: { type = "app"; program = pkgs.lib.getExe drv; };

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

}
