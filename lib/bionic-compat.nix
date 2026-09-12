# lib/bionic-compat.nix
# Composed Bionic libc compatibility overlays for Android targets.

{ lib }:

lib.composeManyExtensions [
  (import ./overlays/sysroot.nix { inherit lib; })
  (import ./overlays/stdenv.nix { inherit lib; })
  (import ./overlays/llvm.nix { inherit lib; })
]
