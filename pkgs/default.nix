# pkgs/default.nix
# Package collection for bionic-pkgs evaluated against targetPackages.

{ targetPkgs }:

let
  self = {
    # Core Compatibility Libraries & Shims
    bionic-compat = targetPkgs.callPackage ./libs/bionic-compat { };
    android-headers = targetPkgs.callPackage ./libs/android-headers { };
    libffi = targetPkgs.callPackage ./libs/libffi {
      inherit (targetPkgs) bionicFixupHook;
      inherit (self) bionic-compat;
    };

    # Diagnostics & System Tracing
    strace = targetPkgs.callPackage ./diagnostics/strace {
      inherit (targetPkgs) bionicFixupHook;
      inherit (self) bionic-compat;
    };

    # Runtime Environments & Interpreters
    python3 = targetPkgs.callPackage ./runtime/python3 {
      inherit (targetPkgs) bionicFixupHook;
      inherit (self) bionic-compat libffi android-headers;
    };
  };
in
self
