# pkgs/libs/libedit/default.nix
# NetBSD Editline library (libedit) BSD replacement for GNU readline for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libedit";
  version = "20240808-3.1";

  src = fetchurl {
    url = "https://www.thrysoee.dk/editline/libedit-${finalAttrs.version}.tar.gz";
    hash = "sha256-XwVzNJ13xKSJZxkc3WY03Xql9jmMalf+A3zAJpbWCZ8=";
  };

  buildInputs = [
    ncurses
  ];

  configureFlags = [
    "--enable-shared"
    "--enable-static"
    "--disable-examples"
  ];

  # Android Bionic porting shims:
  # 1. -D__STDC_ISO_10646__=200009L: Bionic wchar_t uses UTF-32/ISO 10646, but wchar.h doesn't define __STDC_ISO_10646__.
  # 2. -DHAVE_SIZE_MAX: Prevents sys.h from redefining SIZE_MAX which conflicts with Bionic stdint.h.
  # 3. -DNBBY=8: Bionic <sys/param.h> lacks BSD NBBY (Number of Bits per BYte), required by src/vis.c.
  env = {
    NIX_CFLAGS_COMPILE = "-D__STDC_ISO_10646__=200009L -DHAVE_SIZE_MAX -DNBBY=8";
  };

  enableParallelBuilding = true;

  meta = {
    description = "Command line editor library providing generic line editing, history, and tokenization functions";
    homepage = "https://www.thrysoee.dk/editline/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
