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

  enableParallelBuilding = true;

  meta = {
    description = "Command line editor library providing generic line editing, history, and tokenization functions";
    homepage = "https://www.thrysoee.dk/editline/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
