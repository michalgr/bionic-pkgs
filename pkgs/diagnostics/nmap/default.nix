# pkgs/diagnostics/nmap/default.nix
# Nmap network scanner, Ncat, and Nping for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  pkg-config,
  libpcap,
  openssl,
  pcre2,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "nmap";
  version = "7.991";

  src = fetchurl {
    url = "https://nmap.org/dist/nmap-${finalAttrs.version}.tar.bz2";
    hash = "sha256-pdUH8pQ3vvO+3Udx/5qqj8HCoQnduh9bHPEgJ0VpKb4=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    libpcap
    openssl
    pcre2
  ];

  # Bionic Porting Notes:
  # 1. Header Coordination:
  #    In Bionic, <sys/types.h> includes <bits/in_addr.h> defining struct in_addr. Force-including
  #    sys/types.h prevents incomplete type errors for struct in_addr when <netinet/in.h> includes <linux/in.h>.
  # 2. Toolchain Binaries:
  #    Pass target cross-ar and cross-ranlib to makeFlags for subdirectories.
  # 3. Post-Patch Replacements:
  #    - liblua/Makefile: Preserve archiver flags ('rcu') when invoking $(AR) $@.
  #    - libdnet-stripped: Explicitly cast route_gw IPv6 address to (const struct in6_addr *).
  #    - nping: Disambiguate ::bind() to avoid conflict in EchoServer.
  #    - ncat: Replace /bin/sh with /system/bin/sh for native Android compatibility.
  #    - ncat: Define SUN_LEN macro in sockaddr_u.h (missing in Bionic <sys/un.h>).
  NIX_CFLAGS_COMPILE = [
    "-include sys/types.h"
  ];

  makeFlags = [
    "AR=${stdenv.cc.bintools.targetPrefix}ar"
    "RANLIB=${stdenv.cc.bintools.targetPrefix}ranlib"
  ];

  configureFlags = [
    "--with-libpcap=${libpcap}"
    "--with-openssl=${openssl}"
    "--with-libz"
    "--with-libpcre=${pcre2}"
    "--with-liblua=included"
    "--with-liblinear=included"
    "--with-libdnet=included"
    "--without-libssh2"
    "--without-ndiff"
    "--without-zenmap"
  ];

  postPatch = ''
        substituteInPlace liblua/Makefile \
          --replace-fail '$(AR) $@' '$(AR) rcu $@'

        substituteInPlace libdnet-stripped/src/route-linux.c \
          --replace-fail "!IN6_IS_ADDR_UNSPECIFIED(&entry->route_gw.addr_ip6)" \
                         "!IN6_IS_ADDR_UNSPECIFIED((const struct in6_addr *)&entry->route_gw.addr_ip6)"

        substituteInPlace nping/EchoServer.cc \
          --replace-fail "bind(master_sd" "::bind(master_sd"

        substituteInPlace ncat/ncat_posix.c \
          --replace-fail '"/bin/sh"' '"/system/bin/sh"'

        substituteInPlace ncat/ncat_main.c \
          --replace-fail '"/bin/sh"' '"/system/bin/sh"'

        substituteInPlace ncat/sockaddr_u.h \
          --replace-fail '#if HAVE_SYS_UN_H' '#if HAVE_SYS_UN_H
    #ifndef SUN_LEN
    #include <string.h>
    #define SUN_LEN(ptr) ((sizeof(*(ptr)) - sizeof((ptr)->sun_path)) + strlen((ptr)->sun_path))
    #endif'
  '';

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Network discovery and security auditing tool suite (nmap, ncat, nping)";
    homepage = "https://nmap.org/";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "nmap";
  };
})
