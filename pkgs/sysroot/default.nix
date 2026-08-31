# pkgs/sysroot/default.nix
# Android sysroot runtime bundle archive.

{ stdenv, gnutar, gzip, lib }:

{ packages, targetArch ? stdenv.hostPlatform.parsed.cpu.name }:

stdenv.mkDerivation {
  pname = "sysroot-${targetArch}";
  version = "1.0.0";

  nativeBuildInputs = [ gnutar gzip ];

  packagePaths = map (p: "${p}") packages;

  buildCommand = ''
    mkdir -p staging/bin staging/lib staging/share

    for pkg in $packagePaths; do
      chmod -R u+w staging 2>/dev/null || true

      if [ -d "$pkg/bin" ]; then
        cp -a "$pkg/bin/." staging/bin/
        chmod -R u+w staging 2>/dev/null || true
      fi
      if [ -d "$pkg/lib" ]; then
        for item in "$pkg"/lib/*; do
          [ -e "$item" ] || continue
          base="$(basename "$item")"
          case "$base" in
            *.a|*.la|*.o|pkgconfig|cmake)
              ;;
            *)
              cp -a "$item" staging/lib/
              chmod -R u+w staging 2>/dev/null || true
              ;;
          esac
        done
      fi
      if [ -d "$pkg/share" ]; then
        for item in "$pkg"/share/*; do
          [ -e "$item" ] || continue
          base="$(basename "$item")"
          case "$base" in
            man|doc|info|locale|aclocal|pkgconfig|gdb)
              ;;
            *)
              cp -a "$item" staging/share/
              chmod -R u+w staging 2>/dev/null || true
              ;;
          esac
        done
      fi
    done

    # Clean up unwanted static archives or pkgconfig inside staging
    chmod -R u+w staging 2>/dev/null || true
    find staging -type f \( -name "*.a" -o -name "*.la" -o -name "*.o" \) -delete 2>/dev/null || true
    find staging -type d \( -name "pkgconfig" -o -name "cmake" \) -exec rm -rf {} + 2>/dev/null || true

    # Remove empty dirs
    [ -d staging/lib ] && [ -z "$(ls -A staging/lib)" ] && rmdir staging/lib || true
    [ -d staging/share ] && [ -z "$(ls -A staging/share)" ] && rmdir staging/share || true

    # Create python-launcher.sh at root of extracted sysroot
    cat << 'EOF' > staging/python-launcher.sh
#!/system/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$SCRIPT_DIR/lib" ]; then
  BASE_DIR="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../lib" ]; then
  BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  BASE_DIR="$SCRIPT_DIR"
fi

export LD_LIBRARY_PATH="$BASE_DIR/lib:$LD_LIBRARY_PATH"
export PATH="$BASE_DIR/bin:$PATH"

for py_dir in "$BASE_DIR"/lib/python3.*; do
  if [ -d "$py_dir" ]; then
    export PYTHONHOME="$BASE_DIR"
    if [ -d "$py_dir/site-packages" ]; then
      export PYTHONPATH="$py_dir/site-packages:${PYTHONPATH:-}"
    fi
    break
  fi
done

if [ -x "$BASE_DIR/bin/python3" ]; then
  exec "$BASE_DIR/bin/python3" "$@"
else
  echo "Executable $BASE_DIR/bin/python3 not found" >&2
  exit 1
fi
EOF
    chmod 755 staging/python-launcher.sh

    mkdir -p $out
    tar -czf "$out/sysroot-${targetArch}.tar.gz" -C staging .
  '';

  meta = {
    description = "Android sysroot runtime bundle archive (${targetArch})";
    skipElfCheck = true;
  };
}
