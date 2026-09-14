# pkgs/core/tmux/default.nix
# Terminal multiplexer for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  pkg-config,
  bison,
  ncurses,
  libevent,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tmux";
  version = "3.7c";

  src = fetchurl {
    url = "https://github.com/tmux/tmux/releases/download/${finalAttrs.version}/tmux-${finalAttrs.version}.tar.gz";
    hash = "sha256-fGDK6aDiUoji4kdQqvyeiAD8f9RVXkR+GynuQgHPs78=";
  };

  nativeBuildInputs = [
    pkg-config
    bison
  ];

  buildInputs = [
    ncurses
    libevent
  ];

  # Bionic Porting Notes:
  # 1. Header Coordination:
  #    Force-including sys/types.h ensures struct in_addr is defined before <netinet/in.h>
  #    includes <linux/in.h> in compat/htonll.c and compat/ntohll.c.
  # 2. Android Path Adaptations:
  #    - _PATH_TMP: On Android, /tmp does not exist. Defaulting to /data/local/tmp/ ensures
  #      tmux creates its server IPC socket in /data/local/tmp/ without requiring $TMUX_TMPDIR.
  #    - _PATH_BSHELL: Default to /system/bin/sh for native Android compatibility.
  NIX_CFLAGS_COMPILE = [
    "-include sys/types.h"
  ];

  postPatch = ''
    substituteInPlace compat.h \
      --replace-fail '#define _PATH_TMP	"/tmp/"' '#define _PATH_TMP	"/data/local/tmp/"' \
      --replace-fail '#define _PATH_BSHELL	"/bin/sh"' '#define _PATH_BSHELL	"/system/bin/sh"'
  '';

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Terminal multiplexer";
    homepage = "https://tmux.github.io/";
    license = lib.licenses.isc;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "tmux";
  };
})
