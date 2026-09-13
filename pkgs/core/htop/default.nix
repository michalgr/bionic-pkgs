# pkgs/core/htop/default.nix
# htop interactive process viewer for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  pkg-config,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "htop";
  version = "3.5.3";

  src = fetchurl {
    url = "https://github.com/htop-dev/htop/releases/download/${finalAttrs.version}/htop-${finalAttrs.version}.tar.xz";
    hash = "sha256-cWJXlEAmIsI+uATkUv8Vw2x96vG6pB+1SpIYkes0FcI=";
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    ncurses
  ];

  # Bionic Porting Notes:
  # 1. Native Linux Platform Detection:
  #    htop detects $host_os matching "linux-android" as linux platform (my_htop_platform=linux),
  #    activating native Linux /proc/stat, /proc/meminfo, and per-process procfs parsing.
  # 2. Dependency Exclusions for Android Userspace:
  #    - --disable-capabilities: Eliminates libcap dependency (Android uses Bionic direct syscalls).
  #    - --disable-sensors: Eliminates libsensors (absent on Android).
  #    - --disable-delayacct: Eliminates Netlink taskstats libnl-3 dependency.
  #    - --disable-hwloc: Eliminates hwloc hardware locality library.
  #    - --disable-unwind & --without-libunwind: Bionic lacks glibc/nongnu libunwind.
  #    - --disable-backtrace: Android Bionic lacks <execinfo.h> backtrace() symbols.
  # 3. Unicode & Affinity:
  #    - --enable-unicode: Links wide-character ncurses (ncursesw) via pkg-config.
  #    - --enable-affinity: Enables CPU affinity management using Bionic sched_setaffinity().
  configureFlags = [
    "--enable-unicode"
    "--enable-affinity"
    "--disable-capabilities"
    "--disable-sensors"
    "--disable-delayacct"
    "--disable-hwloc"
    "--disable-unwind"
    "--without-libunwind"
    "--disable-backtrace"
    "--disable-static"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Interactive process viewer for Android 14+ (Bionic libc)";
    homepage = "https://htop.dev/";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "htop";
  };
})
