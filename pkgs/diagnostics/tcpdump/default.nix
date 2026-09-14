# pkgs/diagnostics/tcpdump/default.nix
# tcpdump command-line packet analyzer for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  cmake,
  ninja,
  pkg-config,
  libpcap,
  openssl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tcpdump";
  version = "4.99.6";

  src = fetchurl {
    url = "https://www.tcpdump.org/release/tcpdump-${finalAttrs.version}.tar.gz";
    hash = "sha256-WDmSGg9n19j6PazZzUHkTInMuGfoptshbWJijH/RSwk=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    libpcap
    openssl
  ];

  # Bionic Porting Notes:
  # 1. Native CMake Build:
  #    Automatically locates libpcap and OpenSSL via pkg-config and CMake discovery.
  # 2. Dependency Exclusions:
  #    - -DWITH_SMI=OFF: Disables libsmi (SNMP MIBs, absent on Android).
  #    - -DWITH_CAP_NG=OFF: Disables libcap-ng (absent on Android).
  #    - -DWITH_CAPSICUM=OFF: Disables Capsicum (FreeBSD specific).
  #    - -DWITH_CRYPTO=ON: Enables OpenSSL libcrypto for cryptographic dissectors.
  cmakeFlags = [
    "-DWITH_SMI=OFF"
    "-DWITH_CAP_NG=OFF"
    "-DWITH_CAPSICUM=OFF"
    "-DWITH_CRYPTO=ON"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Command-line packet analyzer";
    homepage = "https://www.tcpdump.org/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "tcpdump";
  };
})
