# pkgs/default.nix
# Package collection for bionic-pkgs evaluated against targetPackages.

{ targetPkgs }:

{
  # Core Compatibility Libraries & Shims
  bionic-compat = targetPkgs.callPackage ./libs/bionic-compat { };

  # Diagnostics & System Tracing
  strace = targetPkgs.callPackage ./diagnostics/strace {
    inherit (targetPkgs) bionicFixupHook bionic-compat;
  };
}
