# pkgs/diagnostics/lldb/default.nix
# LLVM LLDB debugger and lldb-server for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  buildPackages,
  libllvm,
  libclang,
  tblgen,
  libedit,
  ncurses,
  xz,
  zstd,
  libffi,
  python3,
  llvmSrc,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "lldb";
  version = llvmSrc.version;
  src = llvmSrc.src;
  sourceRoot = "llvm-project-${finalAttrs.version}.src/lldb";

  nativeBuildInputs = [
    buildPackages.cmake
    buildPackages.ninja
    buildPackages.which
    buildPackages.python3
    buildPackages.swig
    tblgen
  ];

  buildInputs = [
    libllvm
    libclang
    libedit
    ncurses
    xz
    zstd
    libffi
    python3
  ];

  postPatch = ''
    # 1. Enable NetBSD libedit header on Android
    substituteInPlace include/lldb/Host/Editline.h \
      --replace-fail '#if !defined(_WIN32) && !defined(__ANDROID__)' '#if !defined(_WIN32)'

    # 2. Include android/HostInfoAndroid.cpp when cross-compiling for Android (bpftrace style)
    substituteInPlace source/Host/CMakeLists.txt \
      --replace-fail 'if (CMAKE_SYSTEM_NAME MATCHES "Android")' 'if (ANDROID OR CMAKE_SYSTEM_NAME MATCHES "Android")'
  '';

  cmakeFlags = [
    # LLVM and Clang target CMake configuration
    "-DLLVM_DIR=${libllvm}/lib/cmake/llvm"
    "-DClang_DIR=${libclang}/lib/cmake/clang"

    # Android target platform configuration
    (lib.cmakeBool "ANDROID" true)
    (lib.cmakeBool "LLDB_INCLUDE_TESTS" false)
    (lib.cmakeBool "LLVM_ENABLE_RTTI" true)
    (lib.cmakeFeature "LLDB_CODESIGN_IDENTITY" "")

    # Python scripting support
    "-DPython3_EXECUTABLE=${buildPackages.python3.interpreter}"
    "-DPython3_INCLUDE_DIR=${python3}/include/python${lib.versions.majorMinor python3.version}"
    "-DPython3_INCLUDE_DIRS=${python3}/include/python${lib.versions.majorMinor python3.version}"
    "-DPython3_LIBRARY=${python3}/lib/libpython${lib.versions.majorMinor python3.version}.so"
    "-DPython3_LIBRARIES=${python3}/lib/libpython${lib.versions.majorMinor python3.version}.so"
    (lib.cmakeBool "LLDB_ENABLE_PYTHON" true)
    (lib.cmakeBool "LLDB_ENABLE_SWIG" true)
    "-DSWIG_EXECUTABLE=${buildPackages.swig}/bin/swig"
    "-DLLDB_PYTHON_RELATIVE_PATH=lib/python${lib.versions.majorMinor python3.version}/site-packages"
    "-DLLDB_PYTHON_EXE_RELATIVE_PATH=bin/python3"
    "-DLLDB_PYTHON_EXT_SUFFIX=.cpython-${lib.replaceStrings ["."] [""] (lib.versions.majorMinor python3.version)}-${stdenv.hostPlatform.parsed.cpu.name}-linux-android.so"

    # Feature toggles
    (lib.cmakeBool "LLDB_ENABLE_CURSES" true)
    (lib.cmakeBool "LLDB_ENABLE_LIBEDIT" true)
    (lib.cmakeBool "LLDB_ENABLE_LZMA" true)
    (lib.cmakeBool "LLDB_ENABLE_ZSTD" true)
    (lib.cmakeBool "LLDB_ENABLE_LUA" false)
    (lib.cmakeBool "LLDB_ENABLE_LIBXML2" false)
    (lib.cmakeBool "LLVM_ENABLE_TERMINFO" false)

    # RPATH and installation settings
    "-DLLDB_NO_INSTALL_DEFAULT_RPATH=ON"
    "-DCMAKE_SKIP_RPATH=ON"

    # Host tablegen tools (bypassing CMake nested NATIVE builds)
    (lib.cmakeBool "LLVM_NATIVE_BUILD" false)
    "-DLLVM_NATIVE_TOOL_DIR=${tblgen}/bin"
    "-DLLVM_TABLEGEN=${tblgen}/bin/llvm-tblgen"
    "-DLLVM_TABLEGEN_EXE=${tblgen}/bin/llvm-tblgen"
    "-DCLANG_TABLEGEN=${tblgen}/bin/clang-tblgen"
    "-DCLANG_TABLEGEN_EXE=${tblgen}/bin/clang-tblgen"
    "-DLLDB_TABLEGEN=${tblgen}/bin/lldb-tblgen"
    "-DLLDB_TABLEGEN_EXE=${tblgen}/bin/lldb-tblgen"
  ];

  postInstall = ''
    rm -rf $out/share/vscode
  '';

  meta = {
    description = "Next-generation high-performance debugger (LLDB & lldb-server) for Android (Bionic)";
    homepage = "https://lldb.llvm.org/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "lldb";
    needsLibcxx = true;
  };
})
