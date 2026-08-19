# pkgs/libs/libffi/default.nix
# Foreign Function Interface library for Android Bionic targets.

{
  lib,
  stdenv,
  fetchurl,
  bionicFixupHook,
  bionic-compat ? null,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libffi";
  version = "3.7.1";

  src = fetchurl {
    url = "https://github.com/libffi/libffi/releases/download/v${finalAttrs.version}/libffi-${finalAttrs.version}.tar.gz";
    hash = "sha256-1emmY43b0lE921RRjrZ+S75vpwe8wBwQ9iEvCgiNgZ0=";
  };

  nativeBuildInputs = [
    bionicFixupHook
  ];

  buildInputs = lib.optional (bionic-compat != null) bionic-compat;

  configureFlags = [
    "--enable-shared"
    "--enable-static"
    "--disable-multi-os-directory"
  ];

  # Silences compiler warnings if needed
  env = lib.optionalAttrs stdenv.cc.isClang {
    NIX_CFLAGS_COMPILE = "-Wno-unused-command-line-argument";
  };

  enableParallelBuilding = true;

  meta = {
    description = "A portable, high level programming interface to various calling conventions";
    homepage = "https://sourceware.org/libffi/";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
