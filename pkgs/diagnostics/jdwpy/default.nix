# pkgs/diagnostics/jdwpy/default.nix
# Python JDWP (Java Debug Wire Protocol) library for Android (Bionic libc).

{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
}:

stdenvNoCC.mkDerivation {
  pname = "jdwpy";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "michalgr";
    repo = "jdwpy";
    rev = "7c684f76c12def5652a20bccf103762d923e9b7a";
    hash = "sha256-peBsvem2B1VFo4tKCrR9nNvhLisjlGzZI0RPS5QOQ2A=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/python${lib.versions.majorMinor python3.version}/site-packages/jdwpy"
    cp -r src/jdwpy/* "$out/lib/python${lib.versions.majorMinor python3.version}/site-packages/jdwpy/"
    runHook postInstall
  '';

  meta = {
    description = "Strongly typed Python implementation of the Java Debug Wire Protocol";
    homepage = "https://github.com/michalgr/jdwpy";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    maintainers = [ ];
    skipElfCheck = true;
  };
}
