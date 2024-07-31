{ pkgs, treefmt-nix }:
# user-provided args
{ nix ? false
, rust ? false
, python ? false
, protobuf ? false
, toml ? false
, yaml ? false
, copyright ? false
, config ? { }
}:
let
  args = {
    inherit nix rust python protobuf toml yaml copyright;
    config = ({ rustfmtPackage ? pkgs.rustfmt, withOpenDir ? false, exclude ? [ ] }: { inherit rustfmtPackage withOpenDir exclude; }) config;
  };

  copyrightFiles = [ "*.rs" ];
in
with pkgs.lib.modules;
treefmt-nix.lib.mkWrapper pkgs {
  config = mkMerge [
    {
      projectRootFile = ".git/config";
      package =
        let
          treefmt = pkgs.treefmt2;
          # remove `.` added automatically by `nix fmt` beacuse it breaks `treefmt` when executed from a subdirectory
          withArgs = pkgs.writeShellScriptBin "treefmt" ''
            args=("$@")
            for i in "''${!args[@]}"; do
              if [[ ''${args[i]} == "." ]]; then
                unset 'args[i]'
              fi
            done
            exec ${treefmt}/bin/treefmt --on-unmatched=debug "''${args[@]}"
          '';
          # `treefmt-nix` fails if the derivation does not have a `version`
          package = withArgs.overrideAttrs (_: _: { version = treefmt.version; });
        in
        package;

      settings.global.excludes = args.config.exclude;
    }

    (mkIf args.nix {
      programs.nixpkgs-fmt.enable = true;
    })

    (mkIf args.rust {
      programs.rustfmt = {
        enable = true;
        edition = "2021";
        package = args.config.rustfmtPackage;
      };
    })

    (mkIf args.python {
      programs.ruff.format = true;
      settings.formatter.ruff-format.options = [ "--no-cache" "--config" "${./fmt-assets/ruff.toml}" ];
    })

    (mkIf args.protobuf {
      settings.formatter.buf = {
        command = (import ./lib.nix pkgs).writeCleanEnvShellApp "buf-format" (with pkgs; [ buf diffutils ]) "buf format -w";
        includes = [ "*.proto" ];
      };
    })

    (mkIf args.toml {
      programs.taplo.enable = true;
      settings.formatter.taplo.options = mkAfter [ "--config" "${./fmt-assets/taplo.toml}" ];
    })

    (mkIf args.yaml {
      programs.yamlfmt.enable = true;
      settings.formatter.yamlfmt.options = [ "-conf" "${./fmt-assets/yamlfmt.yml}" ];
    })

    (mkIf (args.copyright && args.config.withOpenDir) {
      # two mutually exclusive instances of addlicense
      settings.formatter.addlicense = {
        command = pkgs.addlicense;
        options = [ "-f" "${./fmt-assets/copyright-closed.tpl}" ];
        includes = copyrightFiles;
        excludes = [ "open/*" ];
        priority = 1;
      };
      settings.formatter.addlicense-open = {
        command = pkgs.addlicense;
        options = [ "-f" "${./fmt-assets/copyright-open.tpl}" ];
        includes = map (pattern: "open/${pattern}") copyrightFiles;
        priority = 2;
      };
    })

    (mkIf (args.copyright && !args.config.withOpenDir) {
      settings.formatter.addlicense = {
        command = pkgs.addlicense;
        options = [ "-f" "${./fmt-assets/copyright-closed.tpl}" ];
        includes = copyrightFiles;
        priority = 1;
      };
    })
  ];
}
