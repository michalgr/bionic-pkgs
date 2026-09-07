# pkgs/libs/sqlite/default.nix
# SQLite embedded SQL database engine library and CLI tool for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "sqlite";
  version = "3.46.0";

  src = fetchurl {
    url = "https://www.sqlite.org/2024/sqlite-autoconf-3460000.tar.gz";
    hash = "sha256-b45qezNSc3SIFvmztiu9w3Koid6HgtfwSMZTpEdBen0=";
  };

  configureFlags = [
    "--enable-shared"
    "--enable-static"
    "--enable-threadsafe"
  ];

  enableParallelBuilding = true;

  meta = {
    description = "Self-contained, serverless, zero-configuration, transactional SQL database engine";
    homepage = "https://www.sqlite.org/";
    license = lib.licenses.publicDomain;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "sqlite3";
  };
})
