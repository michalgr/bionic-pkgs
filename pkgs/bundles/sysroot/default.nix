# pkgs/bundles/sysroot/default.nix
# Android sysroot runtime bundle archive.

{
  lib,
  stdenv,
  runtimeArchive,
  packages ? [ ],
  targetArch ? stdenv.hostPlatform.parsed.cpu.name,
}:

runtimeArchive {
  pname = "sysroot";
  version = "1.0.0";
  inherit packages targetArch;
  archiveName = "sysroot-${targetArch}.tar.gz";
  launcherProgram = "python3";
  launcherName = "python-launcher.sh";
  meta = {
    description = "Android sysroot runtime bundle archive (${targetArch})";
    homepage = "https://github.com/michalgr/bionic-pkgs";
    license = lib.licenses.mit;
  };
}
