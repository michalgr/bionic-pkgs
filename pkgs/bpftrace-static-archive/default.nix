# pkgs/bpftrace-static-archive/default.nix
# BPFtrace static binary archive.

{
  lib,
  stdenv,
  gnutar,
  gzip,
  bpftrace-static,
  targetArch ? stdenv.hostPlatform.parsed.cpu.name,
}:

stdenv.mkDerivation {
  pname = "bpftrace-static-archive-${targetArch}";
  version = bpftrace-static.version or "1.0.0";

  nativeBuildInputs = [ gnutar gzip ];

  buildCommand = ''
    mkdir -p staging
    cp -a ${bpftrace-static}/. staging/

    chmod -R u+w staging 2>/dev/null || true

    mkdir -p $out
    tar --owner=0 --group=0 --numeric-owner --mtime='@1' --sort=name -czf "$out/bpftrace-static-${targetArch}.tar.gz" -C staging .
  '';

  meta = {
    description = "BPFtrace static binary archive (${targetArch})";
    homepage = "https://github.com/bpftrace/bpftrace";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    skipElfCheck = true;
  };
}
