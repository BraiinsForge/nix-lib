# NixLib

NixLib is a collection of Nix functions and utilities used by BOS, BMC and Tooling.

NixLib consists of:

- Cargo workspace build support (`mkWorkspaceConfig`, `mkBuildProfile`, `buildCrate`)
  - Implemented on top of [crane]
  - Includes pre-configured braiins registry
- Wrapper around [treefmt] and [treefmt-nix]
  - With simple interface for enabling formatters for individual languages
  - Includes common default config for each formatter to match company formatting style
- Collection of smaller utilities
  - `mkApp`, `strftime`, `readYaml`, `mapAttrNames`, `mapAttrValues`, `writeCleanEnvShellApp` and maybe more

### List of Projects Using Nix

[crane]: https://github.com/ipetkov/crane
[treefmt]: https://github.com/numtide/treefmt
[treefmt-nix]: https://github.com/numtide/treefmt-nix
