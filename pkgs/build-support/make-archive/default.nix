# pkgs/build-support/make-archive/default.nix
# Low-level derivation helper for bit-for-bit reproducible archives (.tar.gz, .tar.zst, or .tar).

{
  lib,
  stdenv,
  gnutar,
  gzip,
  zstd ? null,
}:

{
  pname,
  version ? "1.0.0",
  src,
  archiveName ? "${pname}.tar.gz",
  compression ? "gzip",
  meta ? { },
}:

let
  compressionFlag =
    if compression == "gzip" then
      "-czf"
    else if compression == "zstd" then
      "--zstd -cf"
    else if compression == "none" then
      "-cf"
    else
      throw "Unsupported compression method: ${compression}";

  compressionTools =
    if compression == "gzip" then
      [ gzip ]
    else if compression == "zstd" then
      [ zstd ]
    else
      [ ];
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ gnutar ] ++ compressionTools;

  buildCommand = ''
    mkdir -p "$out"
    stageDir=$(mktemp -d)
    if ! cp -al "$src/." "$stageDir/" 2>/dev/null; then
      chmod -R u+w "$stageDir" 2>/dev/null || true
      rm -rf "$stageDir"/*
      cp -a "$src/." "$stageDir/"
    fi
    find "$stageDir" -type d -exec chmod 755 {} +
    tar --owner=0 --group=0 --numeric-owner --mtime='@1' --sort=name \
      --hard-dereference \
      ${compressionFlag} "$out/${archiveName}" -C "$stageDir" .
    rm -rf "$stageDir"
  '';

  meta = {
    description = "Deterministic archive builder";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
    skipElfCheck = true;
  }
  // meta;
}
