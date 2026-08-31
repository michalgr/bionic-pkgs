#!/usr/bin/env bash
# scripts/generate-launcher.sh
# Generates a launcher script for executing binaries in a staged Android sysroot / deployment directory.

set -euo pipefail

BIN_NAME="${1:-python3}"

cat << EOF
#!/system/bin/sh
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"

if [ -d "\$SCRIPT_DIR/lib" ]; then
  BASE_DIR="\$SCRIPT_DIR"
elif [ -d "\$SCRIPT_DIR/../lib" ]; then
  BASE_DIR="\$(cd "\$SCRIPT_DIR/.." && pwd)"
else
  BASE_DIR="\$SCRIPT_DIR"
fi

export LD_LIBRARY_PATH="\$BASE_DIR/lib:\$LD_LIBRARY_PATH"
export PATH="\$BASE_DIR/bin:\$PATH"

for py_dir in "\$BASE_DIR"/lib/python3.*; do
  if [ -d "\$py_dir" ]; then
    export PYTHONHOME="\$BASE_DIR"
    if [ -d "\$py_dir/site-packages" ]; then
      export PYTHONPATH="\$py_dir/site-packages:\${PYTHONPATH:-}"
    fi
    break
  fi
done

if [ -x "\$BASE_DIR/bin/${BIN_NAME}" ]; then
  exec "\$BASE_DIR/bin/${BIN_NAME}" "\$@"
else
  echo "Executable \$BASE_DIR/bin/${BIN_NAME} not found" >&2
  exit 1
fi
EOF
