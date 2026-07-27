pkgs:
# user-provided args
{ mermaid ? true
  # Shell linting for tracked shell sources.
, shell ? false
  # `just --fmt --check` is marked unstable upstream (requires `--unstable`); opt-in.
, justfile ? false
  # Cross-references between docs rot silently as files move.
  # Opt-in, since an existing tree is unlikely to be link-clean the day it is switched on.
, links ? false
, config ? { }
}:
let
  lib = pkgs.lib;

  args = {
    inherit mermaid shell justfile links;
    config = ({ exclude ? [ ] }: { inherit exclude; }) config;
  };

  mermaidCheck = pkgs.buildGoModule {
    pname = "mermaid-check";
    version = "0.0.4";
    src = pkgs.fetchFromGitHub {
      owner = "sammcj";
      repo = "mermaid-check";
      rev = "605c28fe6c784c2959ba44ad2560cf43b0cd72f2";
      hash = "sha256-+AQj7GH8zzEPeZpPxrgsDR94g0PYgTFOB7HHw4/fApw=";
    };
    vendorHash = "sha256-NvqyHH2EHWpIWNupT0V/vboSAuAWhLBBZL1CpwH86z4=";
  };

  # Each checker: { name, command, includes }
  # command receives file paths as arguments, must exit non-zero on failure
  checkers = lib.filter (c: c.enabled) [
    {
      name = "mermaid";
      enabled = args.mermaid;
      includes = [ "*.mermaid" "*.mmd" ];
      # go-mermaid only recognizes .mmd, so we pipe via stdin for .mermaid files
      command = pkgs.writeShellScript "mermaid-check" ''
        ${mermaidCheck}/bin/mermaid-check < "$1"
      '';
    }
    {
      name = "justfile";
      enabled = args.justfile;
      includes = [ "justfile" "**/justfile" "Justfile" "**/Justfile" "*.just" "*.justfile" ];
      # `just --fmt --check` parses the justfile (catching unknown recipe deps,
      # syntax errors, etc.) and verifies it is canonically formatted.
      # Does not modify the file. `--fmt` is unstable, hence `--unstable`.
      command = pkgs.writeShellScript "justfile-check" ''
        ${lib.getExe pkgs.just} --unstable --fmt --check --justfile "$1"
      '';
    }
    {
      name = "links";
      enabled = args.links;
      includes = [ "*.md" "*.markdown" ];
      # `--offline` resolves targets on disk and skips anything remote,
      # so the check stays hermetic and never fails on a flaky host.
      #
      # lychee builds its HTTP client at startup even when `--offline` means it
      # will never be used, and that build needs a CA bundle the scrubbed
      # runtime env does not carry.
      command = pkgs.writeShellScript "link-check" ''
        export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        exec ${lib.getExe pkgs.lychee} --offline --no-progress "$1"
      '';
    }
    {
      name = "shell";
      enabled = args.shell;
      # shellcheck can lint arbitrary filenames when the dialect is known
      # (typically from a shebang), but braiinschk currently discovers only
      # conventional shell script extensions.
      includes = [ "*.sh" "*.bash" ];
      command = pkgs.writeShellScript "shell-check" ''
        exec ${lib.getExe pkgs.shellcheck} -x "$1"
      '';
    }
  ];

  excludeArgs = lib.concatMapStringsSep " "
    (p: ''":(exclude)${p}"'')
    args.config.exclude;
in
pkgs.writeShellApplication {
  name = "braiinschk";
  runtimeInputs = with pkgs; [ gitMinimal ];
  runtimeEnv.PATH = null;
  excludeShellChecks = [ "SC2123" ];
  text = ''
    if ! tree_root=$(git rev-parse --show-toplevel 2>/dev/null); then
      echo "braiinschk: not a git repository" >&2
      exit 1
    fi

    echo "checker root: $tree_root"

    failed=0
    checked=0

    ${lib.concatMapStringsSep "\n" (checker: ''
      # ${checker.name}
      while IFS= read -r file; do
        if [ -n "$file" ]; then
          checked=$((checked + 1))
          if ${checker.command} "$tree_root/$file" 2>&1; then
            echo "  PASS: $file"
          else
            echo "  FAIL: $file" >&2
            failed=$((failed + 1))
          fi
        fi
      done < <(git -C "$tree_root" ls-files -- ${lib.concatMapStringsSep " " (p: ''"${p}"'') checker.includes} ${excludeArgs})
    '') checkers}

    echo ""
    echo "checked $checked files, $failed failed"

    if [ "$failed" -gt 0 ]; then
      exit 1
    fi
  '';
}
