{ nixpkgs, localSystem }: with builtins;
let
  inherit (nixpkgs) lib;

  ######
  # Native packages for this platform
  ######
  # To use, just import it:
  #
  # ```
  # pkgs = utils.pkgs;
  # ```
  pkgs = (import nixpkgs) {
    inherit localSystem;
  };

  ######
  # Packages for a given system with possible additional settings
  ######
  # To use:
  #
  # ```
  # x86_64-linux = mkNixpkgs { arch = "x86_64-unknown-linux-musl"; };
  # aarch64-linux = mkNixpkgs { arch = "aarch64-unknown-linux-musl"; };
  # armv7-linux = mkNixpkgs { arch = "armv7l-unknown-linux-musleabihf"; };
  # x86_64-windows = mkNixpkgs
  #   { arch = "x86_64-w64-mingw32"; extras = { crossSystem.libc = "msvcrt"; crossSystem.useLLVM = true; }; }
  # ;
  # ```
  #
  # Keep in mind to use the correct target triplet.
  #
  # CPU types and such recognized by Nix here:
  # <https://github.com/NixOS/nixpkgs/blob/f6f44561884c3470e2b783683d5dbac42dfc833b/lib/systems/parse.nix#L70>
  mkNixpkgs = { arch, extras ? { } }:
    (import nixpkgs)
      {
        inherit localSystem;
        crossSystem.config = arch;
        config.allowUnsupportedSystem = true;
      } // extras;

  enabled_packages = { artifacts, list, arch }: foldl' lib.recursiveUpdate { } (map
    (n: {
      packages."${n}-${arch}" = artifacts.${arch}.${n};
    })
    (attrNames list));

  #####
  # Helper function for combining sets without 'overwriting' anything but conflicts
  #####
  # Use this to combine several attribute sets into one:
  #
  # ```
  # enabled =
  #   utils.recursiveMerge [
  #     (utils.enabled_packages { inherit artifacts; list = artifacts.aarch64-linux; arch = "aarch64-linux"; })
  #     (utils.enabled_packages { inherit artifacts; list = artifacts.armv7-linux; arch = "armv7-linux"; })
  #     (utils.enabled_packages { inherit artifacts; list = artifacts.x86_64-linux; arch = "x86_64-linux"; })
  #   ]
  # ;
  # ```
  #
  # Using merely // will not recursively merge attribute sets
  #
  # With recursiveMerge:
  # ```
  # { a.b = "hello"; } and { a.c = "world"; } --> { a = { b = "hello"; c = "world"; }; }
  # ```
  #
  # Without using it (that is, by using //):
  # ```
  # { a.b = "hello"; } and { a.c = "world"; } --> { a = { c = "world"; }; }
  # ```
  recursiveMerge =
    let
      recursiveMerge = attrList:
        let
          f = attrPath:
            zipAttrsWith (n: values:
              if tail values == [ ]
              then head values
              else if all isList values
              then unique (concatLists values)
              else if all isAttrs values
              then f (attrPath ++ [ n ]) values
              else last values
            );
        in
        f [ ] attrList;
    in
    recursiveMerge;

  mkDockerImage = { name, tag, crate, arch ? null, binaryName ? "", extraBuildParams ? { } }:
    pkgs.dockerTools.buildImage (recursiveMerge [
      {
        inherit name tag;

        created = "now";
        copyToRoot = with pkgs; [ crate bash coreutils-full ];

        config = {
          Cmd = [ "${crate}/bin/${ if binaryName == "" then name else binaryName }" ];
        };

        architecture = arch;
      }
      extraBuildParams
    ]);
in
{
  inherit pkgs mkNixpkgs enabled_packages recursiveMerge mkDockerImage;
}
