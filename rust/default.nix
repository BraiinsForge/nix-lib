{ pkgs, craneLib, docker-spider, nix-filter, localSystem } @ inputs: {
  mkWorkspaceConfig = import ./mkWorkspaceConfig.nix inputs;
  defineCrate = name: src_path: { env ? { } }: { inherit name src_path env; };
}
