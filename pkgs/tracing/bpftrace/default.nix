# pkgs/tracing/bpftrace/default.nix
# High-level tracing language for Linux eBPF on Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  flex,
  bison,
  xxd,
  llvmPackages,
  libbpf,
  bcc,
  elfutils,
  cereal,
  xz,
  zstd,
  bzip2,
  libffi,
  android-prebuilts,
  static ? false,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = if static then "bpftrace-static" else "bpftrace";
  version = "0.26.1";

  src = fetchFromGitHub {
    owner = "bpftrace";
    repo = "bpftrace";
    tag = "v${finalAttrs.version}";
    hash = "sha256-h3gFnQq48oM5uK07xrykOCSJxhr6dqcyVUDoIKIRREY=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    flex
    bison
    xxd
    llvmPackages.llvm
  ];

  buildInputs = [
    llvmPackages.llvm
    llvmPackages.libclang
    llvmPackages.libcxx
    libbpf
    bcc
    elfutils
    cereal
    xz
    zstd
    bzip2
    libffi
    android-prebuilts
  ];

  postPatch = lib.optionalString static ''
    # 1. Integrate static libzstd with libdw for static linking
    substituteInPlace src/CMakeLists.txt \
      --replace-warn 'set(LIBDW_LIBS LIBBZ2 LIBELF LIBLZMA)' 'add_library(LIBZSTD STATIC IMPORTED)
    set_property(TARGET LIBZSTD PROPERTY IMPORTED_LOCATION ''${LIBZSTD_LIBRARIES})
    set(LIBDW_LIBS LIBBZ2 LIBELF LIBLZMA LIBZSTD)'

    # 2. On Android, zlib is a platform dynamic library linked via -lz in the dynamic block;
    # clear ZLIB_LIBRARIES so CMake doesn't try to link libz.so inside the static library list.
    substituteInPlace CMakeLists.txt \
      --replace-warn 'find_package(ZLIB REQUIRED)' 'find_package(ZLIB REQUIRED)
if(ANDROID)
  set(ZLIB_LIBRARIES "")
endif()'

    # 3. In Clang 21 static builds, link required Clang C++ AST, Sema, and CodeGen components
    substituteInPlace src/ast/CMakeLists.txt \
      --replace-warn 'target_link_libraries(ast PUBLIC libclang_static clangDriver clangFrontend clangCodeGen)' \
                     'target_link_libraries(ast PUBLIC libclang_static clangDriver clangFrontend clangCodeGen clangParse clangSema clangAnalysis clangAST clangASTMatchers clangLex clangBasic clangEdit clangSerialization clangSupport clangRewrite clangRewriteFrontend clangIndex clangIndexSerialization)' \
      --replace-warn 'unlink_transitive_dependency("''${CLANG_EXPORTED_TARGETS}" "LLVM")' \
                     'unlink_transitive_dependency("''${CLANG_EXPORTED_TARGETS}" "LLVM")
  foreach(dep ZLIB::ZLIB -lpthread dl m)
    unlink_transitive_dependency("LLVMSupport;''${llvm_libs}" "''${dep}")
  endforeach()'
  '';

  cmakeFlags = [
    (lib.cmakeBool "ANDROID" true)
    (lib.cmakeBool "ENABLE_MAN" false)
    (lib.cmakeBool "BUILD_TESTING" false)
    (lib.cmakeBool "ENABLE_SKB_OUTPUT" false)
    (lib.cmakeBool "USE_SYSTEM_LIBBPF" true)
    (lib.cmakeBool "STATIC_LINKING" static)
    (lib.cmakeFeature "CMAKE_EXE_LINKER_FLAGS" "-Wl,--gc-sections")
  ] ++ lib.optionals static [
    (lib.cmakeFeature "LIBZSTD_LIBRARIES" "${zstd}/lib/libzstd.a")
  ];

  stripAllList = [ "bin" ];

  postInstall = ''
    # Generate standalone Android shell wrappers in bin/ for all bpftrace tools
    for tool in $out/share/bpftrace/tools/*.bt; do
      if [ -f "$tool" ]; then
        tool_name="$(basename "$tool" .bt)"
        cat << 'EOF' > "$out/bin/$tool_name"
#!/system/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$SCRIPT_DIR/../lib:$LD_LIBRARY_PATH"
exec "$SCRIPT_DIR/bin/bpftrace" "$SCRIPT_DIR/share/bpftrace/tools/$(basename "$0").bt" "$@"
EOF
        chmod 755 "$out/bin/$tool_name"
      fi
    done
  '';

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "High-level tracing language for Linux eBPF / Android (Bionic libc)";
    homepage = "https://github.com/bpftrace/bpftrace";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "bpftrace";
  };
})
