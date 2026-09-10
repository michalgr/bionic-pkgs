# pkgs/libs/libllvm/default.nix
# LLVM core libraries and headers for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  llvmPackages,
}:

let
  baseLibllvm = llvmPackages.libllvm.override {
    libxml2 = null;
    enableTerminfo = false;
  };
in
baseLibllvm.overrideAttrs (old: {
  propagatedBuildInputs = lib.filter (p: !(lib.hasInfix "ncurses" (p.name or ""))) (old.propagatedBuildInputs or [ ]);
  buildInputs = (old.buildInputs or [ ]) ++ [
    llvmPackages.libcxx
  ];
  env = (old.env or { }) // {
    LDFLAGS = "";
  };
  cmakeFlags = (old.cmakeFlags or [ ]) ++ [
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
