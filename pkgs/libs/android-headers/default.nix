# pkgs/libs/android-headers/default.nix
# Official Google Android NDK platform headers (android/log.h, trace.h, sync.h, etc.)

{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "android-headers";
  version = "ndk-r23";

  src = fetchzip {
    url = "https://android.googlesource.com/toolchain/prebuilts/ndk/r23/+archive/6c5fa4c0d3999b9ee932f6acbd430eb2f31f3151/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/android.tar.gz";
    hash = "sha256-pgdoqteJ9jNSFrl3SnxnF12vqUPatDwezERc7o7pWV8=";
    stripRoot = false;
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p "$out/include/android"
    cp -vr * "$out/include/android/"
  '';

  meta = {
    description = "Official Android NDK platform C/C++ headers from Google";
    homepage = "https://developer.android.com/ndk";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
