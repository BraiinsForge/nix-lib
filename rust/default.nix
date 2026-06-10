{ pkgs, loadRustToolchain, ... } @ inputs:
let
  def = type: { path, packageName, binName ? null, env ? { } }: {
    inherit type packageName env;
    relativePath = assert pkgs.lib.assertMsg (builtins.isString path) "crate path must be a string"; path;
    binName =
      if binName == false then false
      else if binName != null then binName else packageName;
  };
in
{
  toolchain = loadRustToolchain (pkgs.extend inputs.fenix.overlays.default);

  mkWorkspaceConfig = import ./mkWorkspaceConfig.nix inputs;

  defineCrate = def "bin";
  defineTrunkCrate = throw "trunk crate support has been removed as it was unused";
  defineTauriCrate = throw "tauri crate support has been removed as it was unused";
}
