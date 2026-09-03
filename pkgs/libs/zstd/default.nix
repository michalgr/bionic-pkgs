# pkgs/libs/zstd/default.nix
# Zstandard compression library (libzstd) and CLI tools for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  cmake,
  ninja,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "zstd";
  version = "1.5.7";

  src = fetchurl {
    url = "https://github.com/facebook/zstd/releases/download/v${finalAttrs.version}/zstd-${finalAttrs.version}.tar.gz";
    hash = "sha256-6zPlH0mhXgI5UM14Jcp0pKK0Pbg1SCWsJPwbfuCeb6M=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  # Point CMake to build/cmake subfolder
  cmakeDir = "../build/cmake";

  # Configure flags for Android Bionic:
  # 1. ZSTD_BUILD_SHARED & ZSTD_BUILD_STATIC: Build both libzstd.so and libzstd.a
  # 2. ZSTD_BUILD_PROGRAMS: Build CLI binaries (zstd, zstdcat, unzstd, etc.)
  # 3. ZSTD_PROGRAMS_LINK_SHARED: Link CLI programs against libzstd.so
  # 4. ZSTD_MULTITHREAD_SUPPORT: Enable multi-threading using Bionic libc pthreads
  # 5. ZSTD_BUILD_TESTS: Disable test suite during cross-compilation
  cmakeFlags = [
    "-DZSTD_BUILD_SHARED=ON"
    "-DZSTD_BUILD_STATIC=ON"
    "-DZSTD_BUILD_PROGRAMS=ON"
    "-DZSTD_PROGRAMS_LINK_SHARED=ON"
    "-DZSTD_MULTITHREAD_SUPPORT=ON"
    "-DZSTD_BUILD_TESTS=OFF"
    "-DZSTD_BUILD_CONTRIB=OFF"
    "-DCMAKE_SKIP_INSTALL_RPATH=ON"
  ];

  doCheck = false;

  meta = {
    description = "Zstandard fast real-time compression algorithm (libzstd) and CLI tools for Android (Bionic)";
    homepage = "https://facebook.github.io/zstd/";
    license = with lib.licenses; [
      bsd3
      gpl2Only
    ];
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "zstd";
  };
})
