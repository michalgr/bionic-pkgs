#!/system/bin/sh
# scripts/env.sh
# Universal environment wrapper for bionic-pkgs runtime bundles and sysroot archives.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$SCRIPT_DIR/lib" ]; then
  BASE_DIR="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../lib" ]; then
  BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  BASE_DIR="$SCRIPT_DIR"
fi

export PATH="$BASE_DIR/bin:$PATH"

if [ -d "$BASE_DIR/share/terminfo" ]; then
  export TERMINFO="$BASE_DIR/share/terminfo"
fi

for py_dir in "$BASE_DIR"/lib/python3.*; do
  if [ -d "$py_dir" ]; then
    export PYTHONHOME="$BASE_DIR"
    if [ -d "$py_dir/site-packages" ]; then
      export PYTHONPATH="$py_dir/site-packages${PYTHONPATH:+:$PYTHONPATH}"
    fi
    if [ -d "$BASE_DIR/share/gdb/python" ]; then
      export PYTHONPATH="$BASE_DIR/share/gdb/python${PYTHONPATH:+:$PYTHONPATH}"
    fi
    break
  fi
done

# Process optional leading KEY=VALUE environment variable assignments
while [ $# -gt 0 ]; do
  case "$1" in
    *=*)
      export "$1"
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -eq 0 ]; then
  exec /system/bin/sh
else
  exec "$@"
fi
