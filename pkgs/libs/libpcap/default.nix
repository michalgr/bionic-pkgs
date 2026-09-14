# pkgs/libs/libpcap/default.nix
# Packet capture library (libpcap) for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  cmake,
  ninja,
  flex,
  bison,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libpcap";
  version = "1.10.6";

  src = fetchurl {
    url = "https://www.tcpdump.org/release/libpcap-${finalAttrs.version}.tar.gz";
    hash = "sha256-hy3REzf+GrAq2dT+4EfJ2iRNaVxt3zTi67cz79Ttiqk=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    flex
    bison
  ];

  # Bionic Porting Notes:
  # 1. Standard Linux Packet Sockets:
  #    Builds native pcap-linux.c using AF_PACKET kernel sockets supported by Android kernels.
  # 2. Dependency Exclusions:
  #    Disables unnecessary hardware capture/sniffing backends (USB, Bluetooth, Netmap, RDMA, DAG, DBus, Remote).
  # 3. Shared Library:
  #    Builds libpcap.so with 16 KB page alignment and standard $ORIGIN/../lib RUNPATH.
  # 4. Header Coordination:
  #    In Bionic, <sys/types.h> includes <bits/in_addr.h> defining struct in_addr before <linux/in.h>.
  #    Force-including <sys/types.h> prevents incomplete type errors in gencode.c during compilation.
  NIX_CFLAGS_COMPILE = [
    "-include sys/types.h"
  ];

  cmakeFlags = [
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_MANDIR=share/man"
    "-DENABLE_PROFILING=OFF"
    "-DDISABLE_LINUX_USBMON=ON"
    "-DDISABLE_BLUETOOTH=ON"
    "-DDISABLE_NETMAP=ON"
    "-DDISABLE_RDMA=ON"
    "-DDISABLE_DAG=ON"
    "-DDISABLE_SEPTEL=ON"
    "-DDISABLE_SNF=ON"
    "-DDISABLE_TC=ON"
    "-DDISABLE_DBUS=ON"
    "-DENABLE_REMOTE=OFF"
    "-DBUILD_SHARED_LIBS=ON"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Packet capture library";
    homepage = "https://www.tcpdump.org/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
