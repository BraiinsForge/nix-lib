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
}:
{
  mkBuildProfile = import ./mkBuildProfile.nix inputs {
    inherit src workspacePath env nativeDeps targetDeps disableKeepGoing includeExtraSrc sccache;
    patchSourceInfo = if sourceInfo != null then inputs.patchSourceInfo sourceInfo else x: x;
  };
}
