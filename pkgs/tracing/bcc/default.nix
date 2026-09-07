# pkgs/tracing/bcc/default.nix
# BPF Compiler Collection (BCC) for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchFromGitHub,
  buildPackages,
  cmake,
  flex,
  bison,
  pkg-config,
  llvmPackages,
  elfutils,
  libbpf,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "bcc";
  version = "0.37.0";

  src = fetchFromGitHub {
    owner = "iovisor";
    repo = "bcc";
    tag = "v${finalAttrs.version}";
    hash = "sha256-OfQWqZ7yyN+rs6PJP5QUIn07QdxOiBoUEetGQPp6KJo=";
  };

  nativeBuildInputs = [
    cmake
    flex
    bison
    pkg-config
    buildPackages.python3
    buildPackages.python3Packages.setuptools
    llvmPackages.llvm
  ];

  buildInputs = [
    llvmPackages.llvm
    llvmPackages.libclang
    llvmPackages.libcxx
    elfutils
    libbpf
  ];

  postPatch = ''
    substituteInPlace introspection/bps.c \
      --replace-warn "bzero(&prog_info, sizeof(prog_info));" "memset(&prog_info, 0, sizeof(prog_info));"
    substituteInPlace src/cc/libbcc.pc.in \
      --replace-warn 'libdir=''${exec_prefix}/@CMAKE_INSTALL_LIBDIR@' 'libdir=''${prefix}/lib'
    substituteInPlace src/python/bcc/perf.py \
      --replace-warn "ct.CDLL('libc.so.6'" "ct.CDLL('libc.so'"
    substituteInPlace src/python/bcc/__init__.py \
      --replace-warn "ct.CDLL('librt.so.1'" "ct.CDLL('libc.so'"
  '';

  cmakeFlags = [
    (lib.cmakeFeature "REVISION" finalAttrs.version)
    (lib.cmakeBool "ENABLE_USDT" true)
    (lib.cmakeBool "ENABLE_CPP_API" true)
    (lib.cmakeBool "CMAKE_USE_LIBBPF_PACKAGE" true)
    (lib.cmakeBool "ENABLE_LIBDEBUGINFOD" false)
    (lib.cmakeBool "ENABLE_EXAMPLES" false)
    (lib.cmakeBool "ENABLE_MAN" false)
    (lib.cmakeBool "ENABLE_TESTS" false)
    (lib.cmakeBool "RUN_LUA_TESTS" false)
    (lib.cmakeBool "ENABLE_LLVM_SHARED" true)
  ];

  postInstall = ''
    mkdir -p $out/bin $out/lib/python3.13/site-packages/bcc

    # 1. Install bcc Python module and version file
    cp -a ../src/python/bcc/* $out/lib/python3.13/site-packages/bcc/
    cat << EOF > $out/lib/python3.13/site-packages/bcc/version.py
__version__ = "${finalAttrs.version}"
EOF

    # 2. Expose bps introspection executable
    if [ -f "$out/share/bcc/introspection/bps" ]; then
      mv "$out/share/bcc/introspection/bps" "$out/bin/bps"
      rmdir "$out/share/bcc/introspection" 2>/dev/null || true
    fi

    # 3. Generate standalone Android launchers for all BCC Python tools in bin/
    for tool in $out/share/bcc/tools/*; do
      if [ -x "$tool" ] && [ ! -d "$tool" ]; then
        tool_name="$(basename "$tool")"
        cat << 'EOF' > "$out/bin/$tool_name"
#!/system/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_DIR="$SCRIPT_DIR"

if [ -x "$BASE_DIR/bin/python3" ]; then
  PY_EXEC="$BASE_DIR/bin/python3"
elif [ -x "$BASE_DIR/../python3/run.sh" ]; then
  PY_EXEC="$BASE_DIR/../python3/run.sh"
elif [ -x "$BASE_DIR/../python3/bin/python3" ]; then
  PY_EXEC="$BASE_DIR/../python3/bin/python3"
else
  PY_EXEC="python3"
fi

export LD_LIBRARY_PATH="$BASE_DIR/lib:$BASE_DIR/../lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="$BASE_DIR/lib/python3.13/site-packages:${PYTHONPATH:-}"

exec "$PY_EXEC" "$BASE_DIR/share/bcc/tools/$(basename "$0")" "$@"
EOF
        chmod 755 "$out/bin/$tool_name"
      fi
    done
  '';

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Dynamic Tracing Tools for Linux / Android (Bionic libc)";
    homepage = "https://iovisor.github.io/bcc/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "bps";
  };
})
