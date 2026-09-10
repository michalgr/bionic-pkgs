# pkgs/libs/libllvm/default.nix
# LLVM core libraries and headers for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  buildPackages,
  llvmPackages,
  buildLlvmPackages ? buildPackages.llvmPackages,
}:

let
  baseLibllvm = llvmPackages.libllvm.override {
    inherit buildLlvmPackages;
    libxml2 = null;
    enableTerminfo = false;
  };
in
baseLibllvm.overrideAttrs (old: {
  propagatedBuildInputs = lib.filter (p: !(lib.hasInfix "ncurses" (p.name or ""))) (old.propagatedBuildInputs or [ ]);
  buildInputs = (old.buildInputs or [ ]) ++ [
    llvmPackages.libcxx
  ];

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    buildLlvmPackages.tblgen
    buildLlvmPackages.llvm
  ];

  env = (old.env or { }) // {
    LDFLAGS = "";
  };

  cmakeFlags = (lib.filter (flag:
    !(lib.hasPrefix "-DLLVM_TABLEGEN" flag) &&
    !(lib.hasPrefix "-DLLVM_NATIVE_BUILD" flag) &&
    !(lib.hasPrefix "-DLLVM_CONFIG_PATH" flag) &&
    !(lib.hasPrefix "-DLLVM_NATIVE_TOOL_DIR" flag)
  ) (old.cmakeFlags or [ ])) ++ [
    "-DLLVM_TABLEGEN=${buildLlvmPackages.tblgen}/bin/llvm-tblgen"
    "-DLLVM_TABLEGEN_EXE=${buildLlvmPackages.tblgen}/bin/llvm-tblgen"
    "-DLLVM_CONFIG_PATH=${buildLlvmPackages.llvm}/bin/llvm-config"
    "-DLLVM_NATIVE_TOOL_DIR=${buildLlvmPackages.llvm}/bin"
    "-DLLVM_NATIVE_BUILD=OFF"
    "-DLLVM_ENABLE_LIBCXX=ON"
    "-DLLVM_ENABLE_TERMINFO=OFF"
    "-DLLVM_ENABLE_LIBXML2=OFF"
    "-DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON"
    "-DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON"
    "-DLLVM_TARGETS_TO_BUILD=BPF;AArch64;X86;ARM"
    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=sha1"
    "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,--build-id=sha1"
    "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--build-id=sha1"
  ];

  meta = (old.meta or { }) // {
    skipElfCheck = true;
  };
})
