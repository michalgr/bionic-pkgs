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
    zstd = targetPkgs.callPackage ./libs/zstd { };
    bzip2 = targetPkgs.callPackage ./libs/bzip2 { };
    cereal = targetPkgs.callPackage ./libs/cereal { };
    elfutils = targetPkgs.callPackage ./libs/elfutils {
      inherit (self) android-prebuilts xz zstd bzip2;
    };

    # Build Support Utilities
    verify-flags = targetPkgs.callPackage ./build-support/verify-flags { };

    # Diagnostics & System Tracing
    strace = targetPkgs.callPackage ./diagnostics/strace { };

    # Tracing & Kernel Diagnostics
    libbpf = targetPkgs.callPackage ./tracing/libbpf {
      inherit (self) elfutils android-prebuilts;
    };
    bcc = targetPkgs.callPackage ./tracing/bcc {
      inherit (self) elfutils libbpf android-prebuilts python3;
    };
    bpftrace = targetPkgs.callPackage ./tracing/bpftrace {
      inherit (self) elfutils libbpf bcc cereal android-prebuilts xz zstd bzip2 libffi;
      static = false;
    };
    bpftrace-static = targetPkgs.callPackage ./tracing/bpftrace {
      inherit (self) elfutils libbpf bcc cereal android-prebuilts xz zstd bzip2 libffi;
      static = true;
    };

    # Reversing & Binary Analysis
    radare2 = targetPkgs.callPackage ./reversing/radare2 {
      inherit (self) android-prebuilts;
    };
    rizin = targetPkgs.callPackage ./reversing/rizin { };

    # Runtime Environments & Interpreters
    python3 = targetPkgs.callPackage ./runtime/python3 {
      inherit (self) libffi android-prebuilts xz bzip2;
    };

    # Bundled Archives
    sysroot = targetPkgs.callPackage ./bundles/sysroot {
      packages = [
        self.bpftrace
        self.python3
        self.strace
        self.elfutils
        self.radare2
        self.rizin
        self.bcc
        self.libbpf
        self.libffi
        self.xz
        self.zstd
        self.bzip2
        targetPkgs.llvmPackages.libcxx
      ];
    };

    bpftrace-static-archive = targetPkgs.callPackage ./bundles/bpftrace-static-archive {
      inherit (self) bpftrace-static;
    };
  };
in
self
