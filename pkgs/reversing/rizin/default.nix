# pkgs/reversing/rizin/default.nix
# Rizin reverse engineering framework optimized for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  pkg-config,
  meson,
  ninja,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "rizin";
  version = "0.9.1";

  src = fetchurl {
    url = "https://github.com/rizinorg/rizin/releases/download/v${finalAttrs.version}/rizin-src-v${finalAttrs.version}.tar.xz";
    hash = "sha256-esHNfaynr92nQuFUeLH3R/wfgT5Jb+5xg50eEJ5UPco=";
  };

  depsBuildBuild = [
    buildPackages.stdenv.cc
  ];

  nativeBuildInputs = [
    pkg-config
    meson
    ninja
    buildPackages.python3
  ];

  preConfigure = ''
    # Provide Meson cross-file override for host system = 'android'
    # This enables upstream Android branches in Meson scripts (such as librz/debug native backends)
    cat << 'EOF' > bionic-cross.conf
[host_machine]
system = 'android'
EOF
    mesonFlagsArray+=(--cross-file=bionic-cross.conf)
  '';

  postPatch = ''
    # 1. Setup cross-native subprojects for sandboxed cross-compilation (sdb_gen native tool)
    if [ ! -d subprojects/pcre2_cross_native ]; then
      cp -r subprojects/pcre2-10.47 subprojects/pcre2_cross_native
      cp subprojects/packagefiles/pcre2_cross_native/meson.build subprojects/pcre2_cross_native/meson.build
    fi
    if [ ! -d subprojects/softfloat_cross_native ]; then
      ln -s softfloat subprojects/softfloat_cross_native
    fi
  '';

  mesonBuildType = "release";

  # Minimal dependency architecture:
  # Rizin bundles vetted subprojects in its release source distribution for core capabilities
  # (capstone, pcre2, tree-sitter, xxhash, lz4, lzma, zstd, zlib, libzip, libmspack, blake2/3, softfloat, zydis).
  # We disable all optional external system dependencies (openssl, libmagic, libusb, readline, etc.)
  # to produce a self-contained reversing toolset with zero external runtime dependencies.
  mesonFlags = [
    "--default-library=static"
    "-Dblob=true"
    "-Dcli=enabled"
    "-Dportable=true"
    "-Dsubprojects_check=false"
    "-Denable_tests=false"
    "-Denable_rz_test=false"
    "-Denable_benchmarks=false"
    "-Denable_examples=false"
    "-Duse_sys_magic=disabled"
    "-Duse_sys_libzip=disabled"
    "-Duse_sys_zlib=disabled"
    "-Duse_sys_lz4=disabled"
    "-Duse_sys_libzstd=disabled"
    "-Duse_sys_lzma=disabled"
    "-Duse_sys_xxhash=disabled"
    "-Duse_sys_openssl=disabled"
    "-Duse_sys_libmspack=disabled"
    "-Duse_sys_tree_sitter=disabled"
    "-Duse_sys_pcre2=disabled"
    "-Duse_sys_capstone=disabled"
    "-Duse_capstone_version=next"
    "-Duse_sys_softfloat=disabled"
    "-Duse_sys_blake2=disabled"
    "-Duse_sys_blake3=disabled"
    "-Duse_sys_zydis=disabled"
    "-Dinstall_sigdb=false"
    "-Dregenerate_cmds=disabled"
  ];

  patches = [
    ./disable-io-shm-on-android.patch
  ];

  meta = {
    description = "UNIX-like reverse engineering framework and command-line toolset";
    homepage = "https://rizin.re/";
    license = with lib.licenses; [
      gpl3Plus
      lgpl3Plus
    ];
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "rizin";
  };
})
