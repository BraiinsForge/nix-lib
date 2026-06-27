# TODO: this is redundant now, refactor later

# inherited args
inputs:
# this fn's args
{ src
, workspacePath ? ""
, sourceInfo ? null
, env ? { }
, nativeDeps ? _: [ ]
, targetDeps ? _: [ ]
  # https://crane.dev/API.html#cranelibstdenvselector
, stdenvSelector ? (p: p.stdenv)
, disableKeepGoing ? false
, sccache ? true
, timings ? true
}:
{
  mkBuildProfile = import ./mkBuildProfile.nix inputs {
    inherit src workspacePath env nativeDeps targetDeps stdenvSelector disableKeepGoing sccache timings;
    patchSourceInfo = if sourceInfo != null then inputs.patchSourceInfo sourceInfo else x: x;
  };
}
