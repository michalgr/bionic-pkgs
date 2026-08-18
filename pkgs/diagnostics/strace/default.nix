# pkgs/diagnostics/strace/default.nix
# Strace derivation optimized for Android 14+ (Bionic libc) cross-compilation.

{
  lib,
  stdenv,
  fetchurl,
  perl,
  buildPackages,
  bionicFixupHook,
  bionic-compat ? null,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "strace";
  version = "7.1";

  src = fetchurl {
    url = "https://strace.io/files/${finalAttrs.version}/strace-${finalAttrs.version}.tar.xz";
    hash = "sha256-gXQ+zypbRBhrL1A4r9yL7aflxwrtFbT7+8xuns4kSQ8=";
  };

  # Native compiler for build machine (CC_FOR_BUILD):
  # During build, strace builds and runs native helper utilities (such as ioctlsort0
  # and ioctlsort1) to generate sorted ioctl lookup tables. Providing buildPackages.stdenv.cc
  # ensures CC_FOR_BUILD and host linkers are available during cross-compilation.
  depsBuildBuild = [
    buildPackages.stdenv.cc
  ];

  nativeBuildInputs = [
    perl            # Used by strace build scripts to generate syscall tables and headers
    bionicFixupHook # Rewrites ELF dynamic RUNPATH to relative origin paths ($ORIGIN/../lib:$ORIGIN/lib)
  ];

  buildInputs = lib.optional (bionic-compat != null) bionic-compat;

  # Bionic Porting Notes & Dependency Exclusions:
  # 1. nongnu-libunwind (pkgs.libunwind): Omitted because its coredump/procfs handlers
  #    require glibc's `struct elf_prstatus` in <sys/procfs.h>, which is absent in Android Bionic.
  # 2. elfutils (debuginfod): Omitted to eliminate heavyweight Linux server daemon
  #    dependencies (curl, sqlite, gnutls, tzdata, gettext/NLS) and produce a lightweight standalone tool.

  configureFlags = [
    # Enables Multi-Personality (MPERS) support. MPERS allows a 64-bit strace binary
    # (e.g. aarch64 or x86_64) to properly trace and decode 32-bit processes (e.g. armv7a or i686)
    # with different struct layouts (struct stat, timeval, etc.). Using `check` allows the build
    # to enable multi-personality decoding if supported by the toolchain, while gracefully falling
    # back to single-personality without failing the build if secondary 32-bit multilib headers are absent.
    "--enable-mpers=check"

    # Prevents compiler warnings (e.g., Clang macro redefinitions or Bionic deprecations)
    # from being treated as fatal errors during cross-compilation.
    "--disable-gcc-Werror"
  ];

  # Silences Clang warnings on unused static helper functions without overriding Autotools -O2 defaults
  env = lib.optionalAttrs stdenv.cc.isClang {
    NIX_CFLAGS_COMPILE = "-Wno-unused-function";
  };

  enableParallelBuilding = true;

  meta = {
    description = "Diagnostic, debugging, and instructional userspace tracer for Linux/Android system calls";
    homepage = "https://strace.io/";
    license = with lib.licenses; [
      lgpl21Plus # strace tool and shared libraries (LGPL-2.1-or-later)
      gpl2Plus   # test suite (GPL-2.0-or-later)
    ];
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "strace";
  };
})
