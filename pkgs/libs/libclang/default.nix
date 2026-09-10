# pkgs/libs/libclang/default.nix
# Clang C/C++ AST and parser libraries for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  buildPackages,
  llvmPackages,
  buildLlvmPackages ? buildPackages.llvmPackages,
  libllvm,
}:

let
  baseLibclang = llvmPackages.libclang.override {
    inherit buildLlvmPackages libllvm;
    libxml2 = null;
  };
in
baseLibclang.overrideAttrs (old: {
  buildInputs = (old.buildInputs or [ ]) ++ [
    llvmPackages.libcxx
  ];

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    buildLlvmPackages.tblgen
    buildLlvmPackages.llvm
  ];

  cmakeFlags = (lib.filter (flag:
    !(lib.hasPrefix "-DLLVM_TABLEGEN" flag) &&
    !(lib.hasPrefix "-DCLANG_TABLEGEN" flag) &&
    !(lib.hasPrefix "-DLLVM_NATIVE_BUILD" flag) &&
    !(lib.hasPrefix "-DLLVM_CONFIG_PATH" flag) &&
    !(lib.hasPrefix "-DLLVM_NATIVE_TOOL_DIR" flag)
  ) (old.cmakeFlags or [ ])) ++ [
    "-DLLVM_TABLEGEN=${buildLlvmPackages.tblgen}/bin/llvm-tblgen"
    "-DLLVM_TABLEGEN_EXE=${buildLlvmPackages.tblgen}/bin/llvm-tblgen"
    "-DCLANG_TABLEGEN=${buildLlvmPackages.tblgen}/bin/clang-tblgen"
    "-DCLANG_TABLEGEN_EXE=${buildLlvmPackages.tblgen}/bin/clang-tblgen"
    "-DLLVM_CONFIG_PATH=${buildLlvmPackages.llvm}/bin/llvm-config"
    "-DLLVM_NATIVE_TOOL_DIR=${buildLlvmPackages.llvm}/bin"
    "-DLLVM_NATIVE_BUILD=OFF"
    "-DLLVM_ENABLE_LIBCXX=ON"
    "-DLLVM_ENABLE_LIBXML2=OFF"
    "-DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON"
    "-DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON"
    "-DLLVM_TARGETS_TO_BUILD=BPF;AArch64;X86;ARM"
    "-DLIBCLANG_BUILD_STATIC=ON"
  ];

  meta = (old.meta or { }) // {
    skipElfCheck = true;
  };
})
