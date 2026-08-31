# pkgs/bpftrace-static-archive/default.nix
# BPFtrace static binary archive.

{ stdenv, gnutar, gzip, lib }:

{ bpftrace-static, targetArch ? stdenv.hostPlatform.parsed.cpu.name }:

stdenv.mkDerivation {
  pname = "bpftrace-static-archive-${targetArch}";
  version = bpftrace-static.version or "1.0.0";

  nativeBuildInputs = [ gnutar gzip ];

  buildCommand = ''
    mkdir -p staging
    cp -a ${bpftrace-static}/. staging/

    chmod -R u+w staging 2>/dev/null || true

    mkdir -p $out
    tar -czf "$out/bpftrace-static-${targetArch}.tar.gz" -C staging .
  '';

  meta = {
    description = "BPFtrace static binary archive (${targetArch})";
    skipElfCheck = true;
  };
}
