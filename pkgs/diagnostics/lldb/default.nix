# pkgs/diagnostics/lldb/default.nix
# LLVM LLDB debugger and lldb-server for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  llvmPackages,
  libedit,
  ncurses,
  xz,
  zstd,
}:

let
  baseLldb = llvmPackages.lldb.override {
    inherit libedit;
    libxml2 = null;
    lua5_3 = null;
    makeWrapper = null;
  };
in
baseLldb.overrideAttrs (old: {
  pname = "lldb";

  # Target dependencies
  buildInputs = [
    ncurses
    libedit
    xz
    zstd
    llvmPackages.libllvm
    llvmPackages.libcxx
    (lib.getLib llvmPackages.libclang)
  ];

  # Filter out host bash wrapper hook and swig/lua from nativeBuildInputs
  nativeBuildInputs = lib.filter (p:
    p != null && !(
      let name = p.name or p.pname or ""; in
      lib.hasInfix "make-shell-wrapper" name ||
      lib.hasInfix "make-wrapper" name ||
      lib.hasInfix "swig" name ||
      lib.hasInfix "lua" name
    )
  ) (old.nativeBuildInputs or [ ]);

  # Hermetic CMake configuration for Bionic
  cmakeFlags = (lib.filter (flag:
    !(lib.hasPrefix "-DLLVM_EXTERNAL_LIT" flag)
  ) (old.cmakeFlags or [ ])) ++ [
    "-DLLDB_ENABLE_LUA=OFF"
    "-DLLDB_ENABLE_LIBXML2=OFF"
    "-DLLDB_ENABLE_PYTHON=OFF"
    "-DLLDB_ENABLE_CURSES=ON"
    "-DLLDB_ENABLE_LIBEDIT=ON"
    "-DLLDB_ENABLE_LZMA=ON"
    "-DLLDB_ENABLE_ZSTD=ON"
    "-DLLVM_ENABLE_TERMINFO=OFF"
    "-DLLDB_INCLUDE_TESTS=OFF"
  ];

  # Eliminate host wrapProgram and install checks
  postInstall = ''
    rm -rf $out/share/vscode
  '';
  installCheckPhase = "";

  meta = (old.meta or { }) // {
    description = "Next-generation high-performance debugger (LLDB & lldb-server) for Android (Bionic)";
    homepage = "https://lldb.llvm.org/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "lldb";
  };
})
