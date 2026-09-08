# pkgs/diagnostics/lldb/default.nix
# LLVM LLDB debugger and lldb-server for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  buildPackages,
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

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  # Clear ambient LDFLAGS to ensure Darwin host builders (aarch64-darwin)
  # do not pass target flags to the nested NATIVE tablegen compiler
  env = (old.env or { }) // {
    LDFLAGS = "";
  };

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
  ) (old.nativeBuildInputs or [ ]) ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    buildPackages.llvmPackages.llvm.out
    buildPackages.llvmPackages.clang-unwrapped.out
  ];

  postPatch = (old.postPatch or "") + ''
    substituteInPlace cmake/modules/LLDBStandalone.cmake \
      --replace-warn 'message(FATAL_ERROR "Expected directory for clang-resource-headers not found: ''${CLANG_RESOURCE_DIR}")' \
                     'message(STATUS "Skipping clang-resource-headers check: ''${CLANG_RESOURCE_DIR}")'
  '';

  # Hermetic CMake configuration for Bionic & standalone cross-compilation
  cmakeFlags = (lib.filter (flag:
    !(lib.hasPrefix "-DLLVM_EXTERNAL_LIT" flag) &&
    !(lib.hasPrefix "-DLLVM_NATIVE_BUILD" flag) &&
    !(lib.hasPrefix "-DLLVM_TABLEGEN" flag)
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
  ] ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    "-DLLVM_TABLEGEN=${buildPackages.llvmPackages.llvm.out}/bin/llvm-tblgen"
    "-DLLVM_TABLEGEN_EXE=${buildPackages.llvmPackages.llvm.out}/bin/llvm-tblgen"
    "-DCLANG_TABLEGEN=${buildPackages.llvmPackages.clang-unwrapped.out}/bin/clang-tblgen"
    "-DCLANG_TABLEGEN_EXE=${buildPackages.llvmPackages.clang-unwrapped.out}/bin/clang-tblgen"
    "-DNATIVE_LLVM_DIR=${buildPackages.llvmPackages.libllvm.dev}/lib/cmake/llvm"
    "-DNATIVE_Clang_DIR=${buildPackages.llvmPackages.libclang.dev}/lib/cmake/clang"
    "-DCROSS_TOOLCHAIN_FLAGS_NATIVE=-DCMAKE_C_COMPILER=${buildPackages.stdenv.cc}/bin/cc;-DCMAKE_CXX_COMPILER=${buildPackages.stdenv.cc}/bin/c++"
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
