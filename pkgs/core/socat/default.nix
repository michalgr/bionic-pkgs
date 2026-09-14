# pkgs/core/socat/default.nix
# Socat multipurpose bidirectional relay for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  openssl,
  readline,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "socat";
  version = "1.8.1.3";

  src = fetchurl {
    url = "http://www.dest-unreach.org/socat/download/socat-${finalAttrs.version}.tar.bz2";
    hash = "sha256-JbxkdikrLmFCIJicd7C2/Kh7slJdl0ezGmY5sftgJBg=";
  };

  buildInputs = [
    openssl
    readline
  ];

  # Bionic Porting Notes & Autotools Cross-Compilation Configuration:
  # 1. POSIX Message Queues:
  #    Android Bionic lacks POSIX message queues (<mqueue.h>). Pass --disable-posixmq.
  # 2. Missing/Partial glibc resolv.h:
  #    Android does not provide glibc resolv.h headers. Set ac_cv_header_resolv_h=no.
  # 3. Compiler Type-Checking & Autotools AC_RUN_IFELSE Bypasses:
  #    Setting ac_cv_c_compiler_gnu=yes ensures socat activates CHANCE_TO_TYPECHECK=1,
  #    which causes configure to use compile-only checks (AC_BASIC_TYPE_GCC / AC_TYPEOF_COMPONENT_GCC)
  #    rather than AC_RUN_IFELSE runtime checks that abort during cross-compilation.
  # 4. Standard Linux Termios Bit Shift Offsets:
  #    Explicitly seed termios bitshift offsets for Linux/Android termios structures.
  # 5. C99 snprintf & z-modifier:
  #    Seed ac_cv_have_c99_snprintf and ac_cv_have_z_modifier to satisfy printf capability tests.
  configureFlags = [
    "--disable-posixmq"
    "ac_cv_header_resolv_h=no"
    "ac_cv_c_compiler_gnu=yes"
    "ac_compiler_gnu=yes"
    "ac_cv_have_c99_snprintf=yes"
    "ac_cv_have_z_modifier=yes"
    "sc_cv_getprotobynumber_r="
    "sc_cv_sys_crdly_shift=9"
    "sc_cv_sys_tabdly_shift=11"
    "sc_cv_sys_csize_shift=4"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Multipurpose relay for bidirectional data transfer";
    homepage = "http://www.dest-unreach.org/socat/";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "socat";
  };
})
