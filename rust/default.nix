{ pkgs, craneLib, docker-spider, nix-filter, localSystem } @ inputs: {
  mkWorkspaceConfig = import ./mkWorkspaceConfig.nix inputs;
  defineCrate = name: src_path: { env ? { } }: {
    inherit src_path env;
    package_name = name;
    bin_name = name;
  };
  defineBinCrate = package_name: bin_name: src_path: { env ? { } }: {
    inherit package_name bin_name src_path env;
  };
}
