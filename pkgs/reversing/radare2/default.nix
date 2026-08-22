# pkgs/reversing/radare2/default.nix
# Radare2 reverse engineering framework optimized for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  pkg-config,
  meson,
  ninja,
  android-prebuilts,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "radare2";
  version = "6.2.0";

  src = fetchurl {
    url = "https://github.com/radareorg/radare2/releases/download/${finalAttrs.version}/radare2-${finalAttrs.version}.tar.xz";
    hash = "sha256-CYSIo6CkwRuJOunnRJbPZVYdF879m38mYaSLS+l7Zjo=";
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

  buildInputs = [
    android-prebuilts
  ];

  preConfigure = ''
    # Provide Meson cross-file override for host system = 'android'
    # This enables upstream Android branches in Meson scripts
    cat << 'EOF' > bionic-cross.conf
[host_machine]
system = 'android'
EOF
    mesonFlagsArray+=(--cross-file=bionic-cross.conf)
  '';

  mesonBuildType = "release";

  # Minimal dependency architecture:
  # Radare2 bundles subprojects (capstone, zydis, qjs, sdb, otezip, etc.).
  # We link against platform libz and build a monolithic blob binary with zero external system dependencies.
  mesonFlags = [
    "--default-library=static"
    "-Dblob=true"
    "-Dcli=enabled"
    "-Dwant_threads=true"
    "-Denable_tests=false"
    "-Denable_r2r=false"
    "-Denable_libfuzzer=false"
    "-Duse_webui=false"
    "-Duse_sys_magic=false"
    "-Duse_sys_zip=false"
    "-Duse_sys_zlib=true"
    "-Duse_sys_lz4=false"
    "-Duse_sys_xxhash=false"
    "-Duse_sys_openssl=false"
    "-Duse_sys_capstone=false"
    "-Duse_sys_zydis=false"
    "-Duse_libuv=false"
    "-Duse_libsqsh=false"
    "-Duse_ssl=false"
    "-Duse_ssl_crypto=false"
  ];

  patches = [
    ./fix-sdb-cross-build.patch
  ];

  postInstall = ''
    # Create radare2 binary target for multi-call dispatcher symlinks
    ln -sf r2blob $out/bin/radare2
    ln -sf radare2 $out/bin/r2pm

    # Remove redundant static copy (r2blob is already static)
    rm -f $out/bin/r2blob.static
  '';

  meta = {
    description = "UNIX-like reverse engineering framework and command-line toolset";
    homepage = "https://radare.org";
    license = with lib.licenses; [
      gpl3Only
      lgpl3Only
    ];
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "radare2";
  };
})
