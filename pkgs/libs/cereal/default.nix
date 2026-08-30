# pkgs/libs/cereal/default.nix
# Header-only C++11 serialization library for Android (Bionic).

{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cereal";
  version = "1.3.2";

  src = fetchFromGitHub {
    owner = "USCiLab";
    repo = "cereal";
    rev = "v${finalAttrs.version}";
    hash = "sha256-HapnwM5oSNKuqoKm5x7+i2zt0sny8z8CePwobz1ITQs=";
  };

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/include
    cp -a include/cereal $out/include/
  '';

  meta = {
    homepage = "https://uscilab.github.io/cereal/";
    description = "Header-only C++11 serialization library";
    license = lib.licenses.bsd3;
    maintainers = [ ];
    platforms = lib.platforms.all;
    skipElfCheck = true;
  };
})
