# pkgs/diagnostics/iperf3/default.nix
# iperf3 active network bandwidth and throughput measurement tool for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  openssl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "iperf";
  version = "3.21";

  src = fetchurl {
    url = "https://downloads.es.net/pub/iperf/iperf-${finalAttrs.version}.tar.gz";
    hash = "sha256-ZW5EBevWIBId587KPq9DqI956huFfQQaagsTFIAazdg=";
  };

  buildInputs = [ openssl ];

  # Bionic Porting Notes:
  # 1. SCTP Exclusion:
  #    Android kernels and standard userland do not provide lksctp. Disable SCTP via --without-sctp.
  # 2. OpenSSL Integration:
  #    Pass --with-openssl pointing to openssl.dev for authenticated tests and crypto support.
  # 3. Dynamic Runtime & Page Alignment:
  #    Bionic stdenv automatically enforces 16 KB page alignment and relative $ORIGIN/../lib RUNPATH.
  configureFlags = [
    "--without-sctp"
    "--with-openssl=${openssl.dev}"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Active network bandwidth and throughput measurement tool";
    homepage = "https://software.es.net/iperf/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "iperf3";
  };
})
