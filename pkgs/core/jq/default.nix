# pkgs/core/jq/default.nix
# Command-line JSON processor for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  oniguruma,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "jq";
  version = "1.7.1";

  src = fetchurl {
    url = "https://github.com/jqlang/jq/releases/download/jq-${finalAttrs.version}/jq-${finalAttrs.version}.tar.gz";
    hash = "sha256-R4ycoSn9LjRD/icxS0VeIR4NjGC8j/ffcDhz3u7lgMI=";
  };

  buildInputs = [
    oniguruma
  ];

  configureFlags = [
    "--with-oniguruma=${oniguruma}"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Lightweight and flexible command-line JSON processor";
    homepage = "https://jqlang.github.io/jq/";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "jq";
  };
})
