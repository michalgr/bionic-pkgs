# pkgs/default.nix
# Package collection for bionic-pkgs evaluated against targetPackages.

{ targetPkgs }:

targetPkgs.lib.makeScope targetPkgs.newScope (self: {
  # Core Compatibility Libraries & Shims
  bionic = targetPkgs.bionic;
  libffi = self.callPackage ./libs/libffi { };
  xz = self.callPackage ./libs/xz { };
  zstd = self.callPackage ./libs/zstd { };
  bzip2 = self.callPackage ./libs/bzip2 { };
  cereal = self.callPackage ./libs/cereal { };
  elfutils = self.callPackage ./libs/elfutils { };

  # Build Support Utilities
  verify-flags = self.callPackage ./build-support/verify-flags { };
  make-archive = self.callPackage ./build-support/make-archive { };
  makeArchive = self.make-archive;
  runtime-archive = self.callPackage ./build-support/runtime-archive { };
  runtimeArchive = self.runtime-archive;

  # Diagnostics & System Tracing
  strace = self.callPackage ./diagnostics/strace { };

  # Tracing & Kernel Diagnostics
  libbpf = self.callPackage ./tracing/libbpf { };
  bcc = self.callPackage ./tracing/bcc { };
  bpftrace = self.callPackage ./tracing/bpftrace { static = false; };
  bpftrace-static = self.callPackage ./tracing/bpftrace { static = true; };

  # Reversing & Binary Analysis
  radare2 = self.callPackage ./reversing/radare2 { };
  rizin = self.callPackage ./reversing/rizin { };

  # Runtime Environments & Interpreters
  python3 = self.callPackage ./runtime/python3 { };

  # Bundled Archives
  sysroot = self.callPackage ./bundles/sysroot {
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
      targetPkgs.llvmPackages.libclang
      targetPkgs.llvmPackages.llvm
    ];
  };

  bpftrace-static-archive = self.callPackage ./bundles/bpftrace-static-archive { };
})
