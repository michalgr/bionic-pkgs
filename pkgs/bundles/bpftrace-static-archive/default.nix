# pkgs/bundles/bpftrace-static-archive/default.nix
# BPFtrace static binary archive.

{
  lib,
  stdenv,
  makeArchive,
  bpftrace-static,
  targetArch ? stdenv.hostPlatform.parsed.cpu.name,
}:

makeArchive {
  pname = "bpftrace-static-${targetArch}";
  version = bpftrace-static.version or "1.0.0";
  src = bpftrace-static;
  archiveName = "bpftrace-static-${targetArch}.tar.gz";
  meta = {
    description = "BPFtrace static binary archive (${targetArch})";
    homepage = "https://github.com/bpftrace/bpftrace";
    license = lib.licenses.asl20;
  };
}
