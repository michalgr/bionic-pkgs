# lib/overlays/llvm.nix
# LLVM toolchain scope overrides for target C++ runtime libraries on Android Bionic targets.

{ lib }:

final: prev:
let
  fixLlvm = import ../llvm-compat.nix {
    inherit lib final;
    bionicFlags = final.bionicFlags;
  };
in
{
  llvmPackages = prev.llvmPackages.overrideScope fixLlvm;
}
// lib.optionalAttrs (prev ? llvmPackages_21) {
  llvmPackages_21 = prev.llvmPackages_21.overrideScope fixLlvm;
}
