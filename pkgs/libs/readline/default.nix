# pkgs/libs/readline/default.nix
# GNU Readline library for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "readline";
  version = "8.3";

  src = fetchurl {
    url = "mirror://gnu/readline/readline-${finalAttrs.version}.tar.gz";
    hash = "sha256-fe5383204467828cd495ee8d1d3c037a7eba1389c22bc6a041f627976f9061cc";
  };

  propagatedBuildInputs = [
    ncurses
  ];

  configureFlags = [
    "--with-curses"
    "--enable-shared"
    "--enable-static"
    "--disable-install-examples"
  ];

  postPatch = ''
    substituteInPlace support/shobj-conf \
      --replace-warn '-Wl,-rpath,$(libdir)' '-Wl,-rpath,\$ORIGIN/../lib'
  '';

  enableParallelBuilding = true;

  meta = {
    description = "GNU Readline library for Android (Bionic)";
    homepage = "https://tiswww.case.edu/php/chet/readline/rltop.html";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
