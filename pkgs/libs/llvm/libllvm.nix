# pkgs/libs/llvm/libllvm.nix
# Standalone target LLVM library (libLLVM.so) and CMake modules for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  buildPackages,
  cmake,
  ninja,
  python3,
  zlib,
  tblgen,
  llvmSrc ? (import ./src.nix { inherit (buildPackages) fetchurl; }),
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libllvm";
  version = llvmSrc.version;
  src = llvmSrc.src;
  sourceRoot = "llvm-project-${finalAttrs.version}.src/llvm";

  nativeBuildInputs = [
    buildPackages.cmake
    buildPackages.ninja
    buildPackages.python3
    tblgen
  ];

  buildInputs = [
    zlib
  ];

  cmakeFlags = [
    (lib.cmakeBool "ANDROID" true)
    (lib.cmakeBool "LLVM_NATIVE_BUILD" false)
    "-DLLVM_TABLEGEN=${tblgen}/bin/llvm-tblgen"
    "-DLLVM_TABLEGEN_EXE=${tblgen}/bin/llvm-tblgen"
    (lib.cmakeFeature "LLVM_HOST_TRIPLE" stdenv.hostPlatform.config)
    (lib.cmakeFeature "LLVM_DEFAULT_TARGET_TRIPLE" stdenv.hostPlatform.config)
    "-DLLVM_TARGETS_TO_BUILD=AArch64;X86;ARM;BPF"
    (lib.cmakeBool "LLVM_BUILD_LLVM_DYLIB" true)
    (lib.cmakeBool "LLVM_LINK_LLVM_DYLIB" true)
    (lib.cmakeBool "LLVM_ENABLE_RTTI" true)
    (lib.cmakeBool "LLVM_ENABLE_FFI" false)
    (lib.cmakeBool "LLVM_ENABLE_TERMINFO" false)
    (lib.cmakeBool "LLVM_ENABLE_LIBXML2" false)
    (lib.cmakeBool "LLVM_ENABLE_LIBEDIT" false)
    (lib.cmakeBool "LLVM_ENABLE_BINDINGS" false)
    (lib.cmakeBool "LLVM_ENABLE_ZSTD" false)
    (lib.cmakeBool "LLVM_BUILD_TOOLS" false)
    (lib.cmakeBool "LLVM_INCLUDE_TESTS" false)
    (lib.cmakeBool "LLVM_INCLUDE_BENCHMARKS" false)
    (lib.cmakeBool "LLVM_INCLUDE_EXAMPLES" false)
    (lib.cmakeBool "LLVM_INSTALL_UTILS" false)
    "-DCMAKE_SKIP_RPATH=ON"
  ];

  meta = {
    description = "LLVM core shared library (libLLVM.so) and headers for Android (Bionic)";
    homepage = "https://llvm.org/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
})
