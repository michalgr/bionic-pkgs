# pkgs/libs/xz/default.nix
# XZ Utils (liblzma) compression library and CLI tools for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "xz";
  version = "5.8.3";

  src = fetchurl {
    url = "https://github.com/tukaani-project/xz/releases/download/v${finalAttrs.version}/xz-${finalAttrs.version}.tar.xz";
    hash = "sha256-//H/zysNqE0wihTeUToaoj1OmqNGTRfmS5cUv90Lv7Y=";
  };

  # Configure flags for Android Bionic:
  # 1. --enable-shared & --enable-static: Produce both liblzma.so and liblzma.a
  # 2. --disable-nls: Disable gettext / NLS to eliminate runtime catalog overhead on Android
  # 3. --disable-microlzma & --disable-lzip-decoder: Keep minimal footprint if needed, or keep standard features
  # 4. --enable-threads=posix: Bionic provides standard POSIX threads directly in libc.so
  configureFlags = [
    "--enable-shared"
    "--enable-static"
    "--disable-nls"
    "--enable-threads=posix"
    "--disable-doc"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "XZ Utils compression library (liblzma) and CLI tools for Android (Bionic)";
    homepage = "https://tukaani.org/xz/";
    license = with lib.licenses; [
      publicDomain
      gpl2Plus
      lgpl21Plus
    ];
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "xz";
  };
})
