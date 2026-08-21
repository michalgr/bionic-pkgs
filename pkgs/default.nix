# pkgs/default.nix
# Package collection for bionic-pkgs evaluated against targetPackages.

{ targetPkgs }:

let
  self = {
    # Core Compatibility Libraries & Shims
    bionic-compat = targetPkgs.callPackage ./libs/bionic-compat { };
    android-prebuilts = targetPkgs.callPackage ./libs/android-prebuilts { };
    libffi = targetPkgs.callPackage ./libs/libffi { };
    elfutils = targetPkgs.callPackage ./libs/elfutils {
      inherit (self) android-prebuilts;
    };

    # Diagnostics & System Tracing
    strace = targetPkgs.callPackage ./diagnostics/strace { };

    # Reversing & Binary Analysis
    rizin = targetPkgs.callPackage ./reversing/rizin { };

    # Runtime Environments & Interpreters
    python3 = targetPkgs.callPackage ./runtime/python3 {
      inherit (self) libffi android-prebuilts;
    };
  };
in
self

