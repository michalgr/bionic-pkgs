# pkgs/libs/android-prebuilts/default.nix
# Official Google Android NDK platform headers and shared library stubs.

{
  lib,
  stdenvNoCC,
  fetchzip,
}:

let
  # Google Android NDK platform headers (public NDK C/C++ API: <android/*.h>, <zlib.h>, <jni.h>, etc.)
  ndkHeaders = fetchzip {
    url = "https://android.googlesource.com/toolchain/prebuilts/ndk/r23/+archive/6c5fa4c0d3999b9ee932f6acbd430eb2f31f3151/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include.tar.gz";
    hash = "sha256-qm91DpoftCh25SL9qQ0RbRqPRetkTIoGdeofdPkVdGQ=";
    stripRoot = false;
  };

  # Google Android NDK r27 platform shared library stubs (API 34 / Android 14+)
  ndkLibs = fetchzip {
    url = "https://android.googlesource.com/toolchain/prebuilts/ndk/r27/+archive/77eba0d553f8f58557f99fa98f327eb5f46e0c8c/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib.tar.gz";
    hash = "sha256-fwiJ0h/wZDTzNwy8WIcw6KdLzgeLedDjZ9nR37zjk2Q=";
    stripRoot = false;
  };

  targetArchDir =
    if stdenvNoCC.targetPlatform.isAarch64 then "aarch64-linux-android"
    else if stdenvNoCC.targetPlatform.isx86_64 then "x86_64-linux-android"
    else if stdenvNoCC.targetPlatform.isArm then "arm-linux-androideabi"
    else if stdenvNoCC.targetPlatform.isi686 then "i686-linux-android"
    else "aarch64-linux-android";
in
stdenvNoCC.mkDerivation {
  pname = "android-prebuilts";
  version = "ndk-r27";

  dontUnpack = true;

  installPhase = ''
    mkdir -p "$out/include" "$out/lib/pkgconfig" "$out/share/pkgconfig"

    # 1. Install all official NDK platform headers
    cp -rL "${ndkHeaders}"/* "$out/include/"

    # 2. Install architecture-specific platform shared library stubs (Android 14 / API 34)
    if [ -d "${ndkLibs}/${targetArchDir}/34" ]; then
      cp -v "${ndkLibs}/${targetArchDir}/34"/*.so "$out/lib/"
    elif [ -d "${ndkLibs}/${targetArchDir}/31" ]; then
      cp -v "${ndkLibs}/${targetArchDir}/31"/*.so "$out/lib/"
    fi

    # 3. Static linker script fallbacks
    echo "INPUT(-lz)" > "$out/lib/libz.a"
    echo "INPUT(-llog)" > "$out/lib/liblog.a"

    # 4. Path-specific pkg-config definitions
    cat << EOF > "$out/lib/pkgconfig/zlib.pc"
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${prefix}/lib
sharedlibdir=\''${prefix}/lib
includedir=\''${prefix}/include

Name: zlib
Description: Android platform zlib compression library
Version: 1.3.2
Requires:
Libs: -L\''${libdir} -lz
Cflags: -I\''${includedir}
EOF
    cp "$out/lib/pkgconfig/zlib.pc" "$out/share/pkgconfig/zlib.pc"
  '';

  meta = {
    description = "Official Google Android NDK platform headers and shared library stubs";
    homepage = "https://developer.android.com/ndk";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
