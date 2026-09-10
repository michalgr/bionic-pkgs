# pkgs/libs/libclang/default.nix
# Clang C/C++ AST and parser libraries for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  llvmPackages,
  libllvm,
}:

let
  baseLibclang = llvmPackages.libclang.override {
    inherit libllvm;
    libxml2 = null;
  };
in
baseLibclang.overrideAttrs (old: {
  buildInputs = (old.buildInputs or [ ]) ++ [
    llvmPackages.libcxx
  ];
  cmakeFlags = (old.cmakeFlags or [ ]) ++ [
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
