# pkgs/default.nix
# Package collection for bionic-pkgs evaluated against targetPackages.

{ targetPkgs }:

let
  self = {
    # Core Compatibility Libraries & Shims
    bionic-compat = targetPkgs.callPackage ./libs/bionic-compat { };
    android-prebuilts = targetPkgs.callPackage ./libs/android-prebuilts { };
    libffi = targetPkgs.callPackage ./libs/libffi { };
    xz = targetPkgs.callPackage ./libs/xz { };
    elfutils = targetPkgs.callPackage ./libs/elfutils {
      inherit (self) android-prebuilts xz;
    };

    # Diagnostics & System Tracing
    strace = targetPkgs.callPackage ./diagnostics/strace { };

    # Tracing & Kernel Diagnostics
    libbpf = targetPkgs.callPackage ./tracing/libbpf {
      inherit (self) elfutils android-prebuilts;
    };
    bcc = targetPkgs.callPackage ./tracing/bcc {
      inherit (self) elfutils libbpf android-prebuilts python3;
    };

    # Reversing & Binary Analysis
    radare2 = targetPkgs.callPackage ./reversing/radare2 {
      inherit (self) android-prebuilts;
    };
    rizin = targetPkgs.callPackage ./reversing/rizin { };

    # Runtime Environments & Interpreters
    python3 = targetPkgs.callPackage ./runtime/python3 {
      inherit (self) libffi android-prebuilts xz;
    };
  };
in
self

