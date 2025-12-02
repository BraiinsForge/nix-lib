{ pkgs ? import <nixpkgs> { } }: { hello = pkgs.writeText "hello" "Hello, World!"; }
