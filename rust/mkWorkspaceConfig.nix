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
let
  workspace_src = builtins.path { path = src; name = "workspace-src"; };
in
{
  mkBuildProfile = import ./mkBuildProfile.nix inputs {
    src = workspace_src;
    inherit workspacePath;
    inherit env nativeDeps targetDeps disableKeepGoing;
    inherit includeExtraSrc;
    inherit sccache;
    patchSourceInfo = if sourceInfo != null then inputs.patchSourceInfo sourceInfo else x: x;
  };
}
