# pkgs/default.nix
# Package collection for bionic-pkgs evaluated against targetPackages.

{ targetPkgs }:

let
  self = {
    # Core Compatibility Libraries & Shims
    bionic-compat = targetPkgs.callPackage ./libs/bionic-compat { };
    android-headers = targetPkgs.callPackage ./libs/android-headers { };
    libffi = targetPkgs.callPackage ./libs/libffi { };

    # Diagnostics & System Tracing
    strace = targetPkgs.callPackage ./diagnostics/strace { };

    # Runtime Environments & Interpreters
    python3 = targetPkgs.callPackage ./runtime/python3 {
      inherit (self) libffi android-headers;
    };
  };
in
self

