# NixLib

NixLib is a collection of Nix functions and utilities used by BOS and Tooling.

NixLib consists of:

- Cargo workspace build support (`mkWorkspaceConfig`, `mkBuildProfile`, `buildCrate`)
  - Implemented on top of [crane] and [docker-spider]
  - Includes pre-configured braiins registry
- Wrapper around [treefmt] and [treefmt-nix]
  - With simple interface for enabling formatters for individual languages
  - Includes common default config for each formatter to match company formatting style
- Collection of smaller utilities
  - `mkApp`, `strftime`, `readYaml`, `mapAttrNames`, `mapAttrValues`, `writeCleanEnvShellApp` and maybe more

[crane]: https://github.com/ipetkov/crane

[docker-spider]: https://gitlab.ii.zone/bos/docker-spider

[treefmt]: https://github.com/numtide/treefmt

[treefmt-nix]: https://github.com/numtide/treefmt-nix

### Projects currently using NixLib

Only projects listed here are supported by the NixLib maintainers. Add a link to your project if you want to receive
free updates and support.

- https://gitlab.ii.zone/tooling/tooling
- https://gitlab.ii.zone/pool/bos-main
- https://gitlab.ii.zone/bos/templates/nix-rust-template
- https://gitlab.ii.zone/bos/crafwler
- https://gitlab.ii.zone/bos/ci-tools
- https://gitlab.ii.zone/tooling/power-price-poller
