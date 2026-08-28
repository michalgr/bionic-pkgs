let
  pkgs = import <nixpkgs> {
    crossSystem = { config = "aarch64-unknown-linux-android"; };
    overlays = [ (import ./lib/bionic-compat.nix { inherit (import <nixpkgs> {}.lib) lib; }) ];
  };
in
  pkgs.bionic-compat
