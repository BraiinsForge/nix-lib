#  Complex justfile fixture exercising many `just` language features
#  for formatter snapshot testing

set shell:=["bash","-euo","pipefail","-c"]
set   dotenv-load   :=true
set  export:=true
set positional-arguments:=true

# variable assignments

name    :="world"
greeting:="hello, " +name
version   :=`echo 1.2.3`
count:=if "a"  ==  "a"  {  "1"  }  else  {  "2"  }
export PATH_EXTRA:="/opt/bin"

# command aliases

alias b   :=build
alias t    :=test

# default recipe with list
default    :
    @just --list --unsorted

# simple recipe with attributes on one line
[private]
[group:"build"]
[confirm("are you sure?")]
build    target="debug"   *args   :
    cargo  build --profile {{target}} {{ args }}

# recipe with dependency and parameter defaults
test    filter="*"   :    build
    cargo   test   --   "{{filter}}"

# recipe with multiple deps on one line
ci:build  test   lint

lint:
    cargo  clippy

# shebang recipe (python)
[no-cd]
py-version:
    #!/usr/bin/env python3
    import sys
    print("python",sys.version_info[:3])

# recipe invoking another recipe
release   version=version   :
    just    build   release
    echo  "releasing  {{ version }}"

# recipe with conditional and string concat
greet    who=name   :
    echo   {{ if who =="world" { "universal greeting" } else { "hello, " +who }  }}

# recipe with backtick
now:
    echo   `date   -u    +%s`

# recipe with variadic star
fmt   +files="." :
    @echo  formatting {{files}}

# linewise continuation
long   :
    curl   -sS   https://example.com \
        | grep  '<title>' \
        | head  -n  1

# module-ish import guard (commented out to keep fixture self-contained)
# import   './other.just'
# mod  sub   'sub-dir'
