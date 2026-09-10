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
  libllvm,
  libclang,
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
    buildPackages.llvmPackages.llvm
  ];

  buildInputs = [
    libllvm
    libclang
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
    substituteInPlace src/python/bcc/libbcc.py \
      --replace-warn "import ctypes as ct" "import os
import ctypes as ct" \
      --replace-warn 'lib = ct.CDLL("libbcc.so.0", use_errno=True)' '_rel_path = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "libbcc.so"))
_so_path = _rel_path if os.path.isfile(_rel_path) else "libbcc.so.0"
lib = ct.CDLL(_so_path, use_errno=True)'
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

if [ -n "''${BCC_PYTHON_BIN:-}" ] && [ -x "$BCC_PYTHON_BIN" ]; then
  PY_EXEC="$BCC_PYTHON_BIN"
elif [ -x "$BASE_DIR/bin/python3" ]; then
  PY_EXEC="$BASE_DIR/bin/python3"
else
  echo "Error: Python 3 interpreter not found for BCC tools." >&2
  echo "Expected at $BASE_DIR/bin/python3." >&2
  echo "Set BCC_PYTHON_BIN=/path/to/python3 to specify an explicit interpreter." >&2
  exit 1
fi

export PYTHONPATH="$BASE_DIR/lib/python3.13/site-packages"

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
