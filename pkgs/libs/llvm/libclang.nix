# pkgs/libs/llvm/libclang.nix
# Standalone target Clang libraries (libclang.so, libclang-cpp.so), headers, and builtin compiler headers for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  buildPackages,
  cmake,
  ninja,
  python3,
  zlib,
  libllvm,
  tblgen,
  llvmSrc,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libclang";
  version = llvmSrc.version;
  src = llvmSrc.src;
  sourceRoot = "llvm-project-${finalAttrs.version}.src/clang";

  nativeBuildInputs = [
    buildPackages.cmake
    buildPackages.ninja
    buildPackages.python3
    tblgen
  ];

  buildInputs = [
    libllvm
    zlib
  ];

  cmakeFlags = [
    (lib.cmakeBool "ANDROID" true)
    (lib.cmakeBool "LLVM_NATIVE_BUILD" false)
    "-DLLVM_NATIVE_TOOL_DIR=${tblgen}/bin"
    "-DLLVM_TABLEGEN=${tblgen}/bin/llvm-tblgen"
    "-DLLVM_TABLEGEN_EXE=${tblgen}/bin/llvm-tblgen"
    "-DCLANG_TABLEGEN=${tblgen}/bin/clang-tblgen"
    "-DCLANG_TABLEGEN_EXE=${tblgen}/bin/clang-tblgen"
    "-DLLVM_DIR=${libllvm}/lib/cmake/llvm"
    (lib.cmakeBool "CLANG_BUILD_TOOLS" false)
    (lib.cmakeBool "CLANG_INCLUDE_TESTS" false)
    (lib.cmakeBool "LLVM_INCLUDE_TESTS" false)
    (lib.cmakeBool "CLANG_ENABLE_LIBXML2" false)
    (lib.cmakeBool "CLANG_ENABLE_STATIC_ANALYZER" true)
    (lib.cmakeBool "CLANG_ENABLE_ARCMT" false)
    (lib.cmakeBool "LIBCLANG_BUILD_STATIC" true)
    "-DCMAKE_SKIP_RPATH=ON"
  ];

  meta = {
    description = "C/C++ front-end libraries (libclang, libclang-cpp) and builtin headers for Android (Bionic)";
    homepage = "https://clang.llvm.org/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    needsLibcxx = true;
  };
})
