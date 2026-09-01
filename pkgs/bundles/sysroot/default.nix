# pkgs/sysroot/default.nix
# Android sysroot runtime bundle archive.

{
  lib,
  stdenv,
  gnutar,
  gzip,
  generateLauncher ? ../../../scripts/generate-launcher.sh,
  packages ? [ ],
  targetArch ? stdenv.hostPlatform.parsed.cpu.name,
}:

stdenv.mkDerivation {
  pname = "sysroot-${targetArch}";
  version = "1.0.0";

  nativeBuildInputs = [ gnutar gzip ];

  packagePaths = map (p: "${p}") packages;

  buildCommand = ''
    mkdir -p staging/bin staging/lib staging/share

    for pkg in $packagePaths; do
      if [ -d "$pkg/bin" ]; then
        cp -a "$pkg/bin/." staging/bin/
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
              ;;
          esac
        done
      fi
      chmod -R u+w staging 2>/dev/null || true
    done

    # Clean up unwanted static archives or pkgconfig inside staging
    find staging -type f \( -name "*.a" -o -name "*.la" -o -name "*.o" \) -delete 2>/dev/null || true
    find staging -type d \( -name "pkgconfig" -o -name "cmake" \) -exec rm -rf {} + 2>/dev/null || true

    # Remove empty dirs
    [ -d staging/lib ] && [ -z "$(ls -A staging/lib)" ] && rmdir staging/lib || true
    [ -d staging/share ] && [ -z "$(ls -A staging/share)" ] && rmdir staging/share || true

    # Create python-launcher.sh at root of extracted sysroot
    bash ${generateLauncher} python3 > staging/python-launcher.sh
    chmod 755 staging/python-launcher.sh

    mkdir -p $out
    tar --owner=0 --group=0 --numeric-owner --mtime='@1' --sort=name -czf "$out/sysroot-${targetArch}.tar.gz" -C staging .
  '';

  meta = {
    description = "Android sysroot runtime bundle archive (${targetArch})";
    homepage = "https://github.com/michalgr/bionic-pkgs";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    skipElfCheck = true;
  };
}
