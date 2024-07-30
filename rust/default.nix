{ pkgs, craneLib, docker-spider, nix-filter, localSystem } @ inputs:
let
  def = type: { path, packageName, binName ? null, env ? { }, extraTauriConf ? {} }: {
    inherit type path packageName env extraTauriConf;
    src_path = path;
    package_name = packageName;
    bin_name = if binName != null then binName else packageName;
  };
in
{
  mkWorkspaceConfig = import ./mkWorkspaceConfig.nix inputs;

  defineCrate' = def "bin";
  defineTrunkCrate = def "trunk";
  defineTauriCrate = def "tauri";

  # TODO: remove and replace with `def "bin"`
  defineCrate = name: src_path: { env ? { } }: {
    inherit src_path env;
    package_name = name;
    bin_name = name;
  };
  defineBinCrate = package_name: bin_name: src_path: { env ? { } }: {
    inherit package_name bin_name src_path env;
  };
}
