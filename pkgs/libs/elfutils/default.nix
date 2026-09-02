# pkgs/libs/elfutils/default.nix
# Minimal elfutils package derivation for Android 14+ (Bionic libc) cross-compilation.

{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  argp-standalone,
  musl-obstack,
  xz,
  zstd,
  bzip2,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "elfutils";
  version = "0.196";

  src = fetchurl {
    url = "https://sourceware.org/elfutils/ftp/${finalAttrs.version}/elfutils-${finalAttrs.version}.tar.bz2";
    hash = "sha256-/VzGt3rWdzysk8s/QV+TGKw7NFXuz4Afa0p0LE9scgk=";
  };

  # elfutils 0.196 includes upstream fixes for aarch64 fregs, strndup, and i386 tlsdesc
  patches = [ ];

  postPatch = ''
    # 1. Disable -Werror so Clang / Bionic macro differences do not halt compilation
    substituteInPlace config/eu.am Makefile.in */Makefile.in \
      --replace-warn "-Werror" ""

    # 2. Provide program_invocation_short_name / program_invocation_name fallback via getprogname()
    cat << 'EOF' >> lib/system.h
#ifndef program_invocation_short_name
# define program_invocation_short_name getprogname ()
#endif
#ifndef program_invocation_name
# define program_invocation_name getprogname ()
#endif
EOF

    # 3. Omit optional srcfiles C++ utility to avoid C++ standard library / libarchive dependencies
    substituteInPlace src/Makefile.in \
      --replace-warn 'srcfiles$(EXEEXT)' ""
  '';

  nativeBuildInputs = [
    buildPackages.m4
    buildPackages.bison
    buildPackages.flex
    buildPackages.pkg-config
    buildPackages.bzip2
  ];

  propagatedBuildInputs = [
    argp-standalone
    musl-obstack
    xz
    zstd
    bzip2
  ];

  # Bionic Porting Notes & Minimal Dependency Architecture:
  # 1. debuginfod / libdebuginfod: Disabled to eliminate heavyweight server daemon dependencies
  #    (curl, sqlite, json-c, libmicrohttpd, libarchive, openssl, krb5).
  # 2. NLS (Native Language Support): Disabled to eliminate gettext runtime dependency.
  # 3. Demangler: Disabled to eliminate libstdc++ / libiberty dependency.
  # 4. Compression: Links against Android platform libz.so, liblzma.so, libzstd.so, and libbz2.so for compressed ELF/DWARF sections.
  # 5. argp & obstack: Sourced from lightweight argp-standalone and musl-obstack shims.
  configureFlags = [
    "--program-prefix=eu-"
    "--enable-deterministic-archives"
    "--disable-debuginfod"
    "--disable-libdebuginfod"
    "--disable-nls"
    "--disable-demangler"
    "--with-bzlib"
    "--with-lzma"
    "--with-zstd"
    "--with-zlib"
    "--without-libiconv-prefix"
    "--without-libintl-prefix"
    "--without-libarchive"
    "--disable-symbol-versioning"
    "--disable-valgrind"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Set of utilities and libraries to handle ELF objects and DWARF debugging information (minimal build)";
    homepage = "https://sourceware.org/elfutils/";
    license = with lib.licenses; [
      gpl2Plus  # elfutils libraries (GPL-2.0-or-later / LGPL-3.0-or-later)
      lgpl3Plus
      gpl3Plus  # CLI binaries
    ];
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "eu-readelf";
  };
})
