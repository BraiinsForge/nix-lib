pkgs: {

  # usage: `out = strftime 1706207938 "%Y-%m-%d_%H-%M-%S";`
  strftime = ts: fmt:
    builtins.readFile (pkgs.runCommand "strftime" { } ''echo -n $(date -d @"${builtins.toString ts}" +"${fmt}") > $out'');

}
