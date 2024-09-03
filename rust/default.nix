{ pkgs, craneLib, docker-spider, nix-filter, localSystem } @ inputs:
let
  def = type: { path, packageName, binName ? null, env ? { }, extraTauriConf ? {} }: {
    inherit type path packageName env extraTauriConf;
    binName = if binName != null then binName else packageName;
  };
in
{
  mkWorkspaceConfig = import ./mkWorkspaceConfig.nix inputs;

  defineCrate = def "bin";
  defineTrunkCrate = def "trunk";
  defineTauriCrate = def "tauri";
}
