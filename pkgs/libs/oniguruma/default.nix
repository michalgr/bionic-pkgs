# pkgs/libs/oniguruma/default.nix
# Oniguruma regular expression library for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "oniguruma";
  version = "6.9.10";

  src = fetchurl {
    url = "https://github.com/kkos/oniguruma/releases/download/v${finalAttrs.version}/onig-${finalAttrs.version}.tar.gz";
    hash = "sha256-Klz8WuJZ5Ol/hraN//wVLNr/6U4gYLdwy4JyONdp/AU=";
  };

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Regular expression library";
    homepage = "https://github.com/kkos/oniguruma";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
