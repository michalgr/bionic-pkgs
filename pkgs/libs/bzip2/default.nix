# pkgs/libs/bzip2/default.nix
# High-quality data compressor (libbz2) and CLI tools for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "bzip2";
  version = "1.0.8";

  src = fetchurl {
    url = "https://sourceware.org/pub/bzip2/bzip2-${finalAttrs.version}.tar.gz";
    hash = "sha256-q1oDF27hBtPw+pDjgdpHjdrkBZGBU8yiSOaCzQxKImk=";
  };

  dontConfigure = true;
  dontPatchShebangs = true;

  postPatch = ''
    # CVE-2016-3189 / CVE-2019-12900: Fix off-by-one buffer boundary in bzip2recover
    substituteInPlace bzip2recover.c \
      --replace-fail 'if (currBlock >= BZ_MAX_HANDLED_BLOCKS)' 'if (currBlock >= BZ_MAX_HANDLED_BLOCKS - 1)'

    # Patch shell scripts for Android /system/bin/sh and /data/local/tmp
    substituteInPlace bzgrep \
      --replace-fail '#!/bin/sh' '#!/system/bin/sh'
    substituteInPlace bzmore \
      --replace-fail '#!/bin/sh' '#!/system/bin/sh'
    substituteInPlace bzdiff \
      --replace-fail '#!/bin/sh' '#!/system/bin/sh' \
      --replace-fail ':-/tmp}' ':-/data/local/tmp}' \
      --replace-fail '/bin/rm' 'rm'
  '';

  buildPhase = ''
    runHook preBuild

    # 1. Compile PIC object files for shared library and tools
    $CC $CFLAGS $NIX_CFLAGS_COMPILE -fPIC -D_FILE_OFFSET_BITS=64 -c \
      blocksort.c huffman.c crctable.c randtable.c compress.c decompress.c bzlib.c

    # 2. Link shared library libbz2.so
    $CC -shared -Wl,-soname,libbz2.so.1.0 $NIX_LDFLAGS -o libbz2.so.${finalAttrs.version} \
      blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o
    ln -sf libbz2.so.${finalAttrs.version} libbz2.so.1.0
    ln -sf libbz2.so.${finalAttrs.version} libbz2.so.1
    ln -sf libbz2.so.${finalAttrs.version} libbz2.so

    # 3. Create static archive libbz2.a
    $AR cq libbz2.a blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o
    $RANLIB libbz2.a

    # 4. Link CLI executables against the shared libbz2.so
    $CC $CFLAGS $NIX_CFLAGS_COMPILE $NIX_LDFLAGS -D_FILE_OFFSET_BITS=64 -o bzip2 bzip2.c -L. -lbz2
    $CC $CFLAGS $NIX_CFLAGS_COMPILE $NIX_LDFLAGS -D_FILE_OFFSET_BITS=64 -o bzip2recover bzip2recover.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib/pkgconfig" "$out/include" "$out/share/man/man1"

    # Install binaries
    cp bzip2 bzip2recover "$out/bin/"
    ln -sf bzip2 "$out/bin/bunzip2"
    ln -sf bzip2 "$out/bin/bzcat"

    # Install scripts & wrappers
    cp bzgrep bzmore bzdiff "$out/bin/"
    chmod +x "$out/bin/bzgrep" "$out/bin/bzmore" "$out/bin/bzdiff"
    ln -sf bzgrep "$out/bin/bzegrep"
    ln -sf bzgrep "$out/bin/bzfgrep"
    ln -sf bzmore "$out/bin/bzless"
    ln -sf bzdiff "$out/bin/bzcmp"

    # Install libraries & header
    cp -P libbz2.so* libbz2.a "$out/lib/"
    cp bzlib.h "$out/include/"

    # Install manpages & symlinks
    cp bzip2.1 bzgrep.1 bzmore.1 bzdiff.1 "$out/share/man/man1/"
    ln -sf bzip2.1 "$out/share/man/man1/bunzip2.1"
    ln -sf bzip2.1 "$out/share/man/man1/bzcat.1"
    ln -sf bzip2.1 "$out/share/man/man1/bzip2recover.1"
    ln -sf bzgrep.1 "$out/share/man/man1/bzegrep.1"
    ln -sf bzgrep.1 "$out/share/man/man1/bzfgrep.1"
    ln -sf bzmore.1 "$out/share/man/man1/bzless.1"
    ln -sf bzdiff.1 "$out/share/man/man1/bzcmp.1"

    # Generate pkg-config metadata file (bzip2.pc)
    cat << EOF > "$out/lib/pkgconfig/bzip2.pc"
prefix=$out
exec_prefix=\$prefix
libdir=\$exec_prefix/lib
includedir=\$prefix/include

Name: bzip2
Description: High-quality data compressor library
Version: ${finalAttrs.version}
Libs: -L\$libdir -lbz2
Cflags: -I\$includedir
EOF

    runHook postInstall
  '';

  doCheck = false;

  meta = {
    description = "High-quality data compressor (libbz2) and CLI tools for Android (Bionic)";
    homepage = "https://sourceware.org/bzip2/";
    license = lib.licenses.bsdOriginal;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "bzip2";
  };
})
