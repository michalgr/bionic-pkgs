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
  libffi,
  python3,
}:

let
  # Standalone host tablegen binary to bypass CMake's nested NATIVE cross-target build
  lldb-tblgen = buildPackages.stdenv.mkDerivation {
    pname = "lldb-tblgen";
    inherit (llvmPackages.lldb) version src;
    sourceRoot = "${llvmPackages.lldb.src.name}/lldb";
    nativeBuildInputs = [
      buildPackages.cmake
      buildPackages.ninja
    ];
    buildInputs = [
      buildPackages.llvmPackages.libllvm
      buildPackages.llvmPackages.libclang
    ];
    cmakeFlags = [
      "-DLLVM_DIR=${buildPackages.llvmPackages.libllvm.dev}/lib/cmake/llvm"
      "-DClang_DIR=${buildPackages.llvmPackages.libclang.dev}/lib/cmake/clang"
      "-DCLANG_RESOURCE_DIR=../../../../${buildPackages.llvmPackages.libclang.lib}"
      "-DLLDB_INCLUDE_TESTS=OFF"
    ];
    ninjaFlags = [ "bin/lldb-tblgen" ];
    installPhase = ''
      mkdir -p $out/bin
      cp bin/lldb-tblgen $out/bin/
    '';
  };

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
    libffi
    python3
    llvmPackages.libllvm
    llvmPackages.libcxx
    (lib.getLib llvmPackages.libclang)
  ];

  # Explicit host build-time tools (cross-compilation is always active for Android targets)
  nativeBuildInputs = [
    buildPackages.cmake
    buildPackages.ninja
    buildPackages.which
    buildPackages.python3
    buildPackages.swig
    buildPackages.llvmPackages.llvm.out
    buildPackages.llvmPackages.clang-unwrapped.out
    lldb-tblgen
  ];

  postPatch = (old.postPatch or "") + ''
    # 1. Enable NetBSD libedit header on Android
    substituteInPlace include/lldb/Host/Editline.h \
      --replace-fail '#if !defined(_WIN32) && !defined(__ANDROID__)' '#if !defined(_WIN32)'

    # 2. Include android/HostInfoAndroid.cpp when cross-compiling for Android (bpftrace style)
    substituteInPlace source/Host/CMakeLists.txt \
      --replace-fail 'if (CMAKE_SYSTEM_NAME MATCHES "Android")' 'if (ANDROID OR CMAKE_SYSTEM_NAME MATCHES "Android")'
  '';

  # Hermetic CMake configuration for Bionic & standalone cross-compilation
  cmakeFlags = (lib.filter (flag:
    !(lib.hasPrefix "-DLLVM_EXTERNAL_LIT" flag) &&
    !(lib.hasPrefix "-DLLVM_NATIVE_BUILD" flag) &&
    !(lib.hasPrefix "-DLLVM_TABLEGEN" flag)
  ) (old.cmakeFlags or [ ])) ++ [
    (lib.cmakeBool "ANDROID" true)
    "-DPython3_EXECUTABLE=${buildPackages.python3.interpreter}"
    "-DPython3_INCLUDE_DIR=${python3}/include/python${lib.versions.majorMinor python3.version}"
    "-DPython3_LIBRARY=${python3}/lib/libpython${lib.versions.majorMinor python3.version}.so"
    "-DPython3_LIBRARIES=${python3}/lib/libpython${lib.versions.majorMinor python3.version}.so"
    "-DLLDB_NO_INSTALL_DEFAULT_RPATH=ON"
    "-DCMAKE_SKIP_RPATH=ON"
    "-DLLDB_ENABLE_LUA=OFF"
    "-DLLDB_ENABLE_LIBXML2=OFF"
    "-DLLDB_ENABLE_PYTHON=ON"
    (lib.cmakeBool "LLDB_ENABLE_SWIG" true)
    "-DSWIG_EXECUTABLE=${buildPackages.swig}/bin/swig"
    "-DLLDB_PYTHON_RELATIVE_PATH=lib/python${lib.versions.majorMinor python3.version}/site-packages"
    "-DLLDB_PYTHON_EXE_RELATIVE_PATH=bin/python3"
    "-DLLDB_PYTHON_EXT_SUFFIX=.cpython-${lib.replaceStrings ["."] [""] (lib.versions.majorMinor python3.version)}-${stdenv.hostPlatform.parsed.cpu.name}-linux-android.so"
    "-DLLDB_ENABLE_CURSES=ON"
    "-DLLDB_ENABLE_LIBEDIT=ON"
    "-DLLDB_ENABLE_LZMA=ON"
    "-DLLDB_ENABLE_ZSTD=ON"
    "-DLLVM_ENABLE_TERMINFO=OFF"
    "-DLLDB_INCLUDE_TESTS=OFF"
    "-DLLVM_TABLEGEN=${buildPackages.llvmPackages.llvm.out}/bin/llvm-tblgen"
    "-DLLVM_TABLEGEN_EXE=${buildPackages.llvmPackages.llvm.out}/bin/llvm-tblgen"
    "-DCLANG_TABLEGEN=${buildPackages.llvmPackages.clang-unwrapped.out}/bin/clang-tblgen"
    "-DCLANG_TABLEGEN_EXE=${buildPackages.llvmPackages.clang-unwrapped.out}/bin/clang-tblgen"
    "-DLLDB_TABLEGEN_EXE=${lldb-tblgen}/bin/lldb-tblgen"
    "-DLLDB_TABLEGEN=${lldb-tblgen}/bin/lldb-tblgen"
  ];

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
