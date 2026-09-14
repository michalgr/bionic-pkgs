# pkgs/libs/libevent/default.nix
# Event notification library for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  cmake,
  ninja,
  openssl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libevent";
  version = "2.1.13";

  src = fetchurl {
    url = "https://github.com/libevent/libevent/releases/download/release-${finalAttrs.version}-stable/libevent-${finalAttrs.version}-stable.tar.gz";
    hash = "sha256-9+k4O4wLqoG2h+W17swBvu+vGxm2QVHZXtYWR/56MVw=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  buildInputs = [
    openssl
  ];

  # Bionic Porting Notes:
  # 1. CMake Policy Minimum:
  #    CMAKE_POLICY_VERSION_MINIMUM=3.5 avoids modern CMake version deprecation warnings/errors.
  # 2. Shared Libraries:
  #    Build shared libraries (libevent.so, libevent_core.so) with 16 KB page alignment and standard RUNPATH.
  # 3. Disable Regress/Tests/Benchmarks:
  #    Avoid building test suites and sample binaries during cross-compilation.
  cmakeFlags = [
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DEVENT__BUILD_SHARED_LIBRARIES=ON"
    "-DEVENT__DISABLE_BENCHMARK=ON"
    "-DEVENT__DISABLE_REGRESS=ON"
    "-DEVENT__DISABLE_SAMPLES=ON"
    "-DEVENT__DISABLE_TESTS=ON"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Event notification library";
    homepage = "https://libevent.org/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
