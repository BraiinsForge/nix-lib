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
, disableKeepGoing ? false
, includeExtraSrc ? [ ]
, sccache ? true
, timings ? true
}:
{
  mkBuildProfile = import ./mkBuildProfile.nix inputs {
    inherit src workspacePath env nativeDeps targetDeps disableKeepGoing includeExtraSrc sccache timings;
    patchSourceInfo = if sourceInfo != null then inputs.patchSourceInfo sourceInfo else x: x;
  };
}
