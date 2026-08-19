# pkgs/runtime/python3/default.nix
# Minimal Python 3 runtime for Android 14+ (Bionic libc) with libffi (ctypes).

{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  pkg-config,
  libffi,
  android-headers,
  bionicFixupHook,
  bionic-compat ? null,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "python3";
  version = "3.13.15";

  src = fetchurl {
    url = "https://www.python.org/ftp/python/${finalAttrs.version}/Python-${finalAttrs.version}.tar.xz";
    hash = "sha256-HmanlFpIOQ7kwqQmig5BhYhAWaE8SqttFIqiCN7qSnY=";
  };

  # Native tooling for build machine:
  # 1. pkg-config: Finds target libffi for _ctypes extension module.
  # 2. bionicFixupHook: Enforces 16 KB page alignment, relative RUNPATH ($ORIGIN/../lib:$ORIGIN/lib),
  #    and prioritizes Bionic compatibility headers and shims.
  nativeBuildInputs = [
    pkg-config
    bionicFixupHook
  ];

  # Host C compiler available during build to compile native generators if needed
  depsBuildBuild = [
    buildPackages.stdenv.cc
  ];

  # Minimalistic dependency set: libffi (for ctypes), android-headers (<android/log.h>), and bionic-compat
  buildInputs = [
    libffi
    android-headers
  ] ++ lib.optional (bionic-compat != null) bionic-compat;

  # Bionic Porting Notes & Dependency Exclusions:
  # 1. Cross-compilation requires --with-build-python matching the major.minor version (3.13).
  # 2. Shared libpython (--enable-shared, --without-static-libpython) is required on Android.
  # 3. Minimal dependency architecture: heavy optional dependencies (readline, curses, sqlite3,
  #    gdbm, dbm, tkinter, idle, test modules) are disabled to produce a fast, standalone runtime.
  # 4. Built-in hashes (--with-builtin-hashlib-hashes): Uses internal HACL* C implementations
  #    so hashlib works without requiring OpenSSL.
  # 5. Native Android logging: Uses <android/log.h> from android-headers and links system liblog.so.
  configureFlags = [
    "--with-build-python=${buildPackages.python313}/bin/python3.13"
    "--enable-shared"
    "--without-static-libpython"
    "--without-ensurepip"
    "--with-system-ffi"
    "--without-readline"
    "--without-curses"
    "--without-sqlite3"
    "--without-gdbm"
    "--without-dbm"
    "--without-tkinter"
    "--disable-test-modules"
    "--with-builtin-hashlib-hashes=md5,sha1,sha2,sha3,blake2"
    "ac_cv_file__dev_ptmx=yes"
    "ac_cv_file__dev_ptc=no"
  ];

  # Android Bionic environment:
  # - __BIONIC_NO_PAGE_SIZE_MACRO: Ensures dynamic page size handling for 16 KB alignment.
  # - -lm: Bionic libm math library linkage.
  env = {
    NIX_CFLAGS_COMPILE = "-D__BIONIC_NO_PAGE_SIZE_MACRO";
    NIX_LDFLAGS = "-lm";
  };

  enableParallelBuilding = true;

  meta = {
    description = "High-level programming language with dynamic typing and minimal dependency set (libffi) for Android (Bionic)";
    homepage = "https://www.python.org/";
    license = lib.licenses.psfl;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "python3";
  };
})
