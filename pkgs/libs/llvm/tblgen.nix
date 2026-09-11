# pkgs/libs/llvm/tblgen.nix
# Native host TableGen suite (llvm-tblgen, clang-tblgen, lldb-tblgen) for LLVM cross-compilation.

{
  lib,
  stdenv,
  cmake,
  ninja,
  python3,
  llvmSrc,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "llvm-tblgen";
  version = llvmSrc.version;
  src = llvmSrc.src;
  sourceRoot = "llvm-project-${finalAttrs.version}.src/llvm";

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  cmakeFlags = [
    "-DLLVM_ENABLE_PROJECTS=clang;lldb"
    (lib.cmakeBool "LLVM_INCLUDE_TESTS" false)
    (lib.cmakeBool "LLVM_INCLUDE_BENCHMARKS" false)
    (lib.cmakeBool "LLVM_INCLUDE_EXAMPLES" false)
    (lib.cmakeBool "LLDB_ENABLE_PYTHON" false)
    (lib.cmakeBool "LLDB_ENABLE_CURSES" false)
    (lib.cmakeBool "LLDB_ENABLE_LIBEDIT" false)
    (lib.cmakeBool "LLVM_ENABLE_LIBXML2" false)
    (lib.cmakeBool "LLDB_ENABLE_LIBXML2" false)
  ];

  ninjaFlags = [
    "llvm-tblgen"
    "clang-tblgen"
    "lldb-tblgen"
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp bin/llvm-tblgen $out/bin/
    cp bin/clang-tblgen $out/bin/
    cp bin/lldb-tblgen $out/bin/
  '';

  meta = {
    description = "Host TableGen tools (llvm-tblgen, clang-tblgen, lldb-tblgen) for LLVM ${finalAttrs.version}";
    homepage = "https://llvm.org/";
    license = lib.licenses.asl20;
    skipElfCheck = true; # Host tool, not an Android target ELF binary
  };
})
