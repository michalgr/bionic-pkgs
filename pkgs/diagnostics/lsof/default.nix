# pkgs/diagnostics/lsof/default.nix
# lsof list open files diagnostic utility for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  groff,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "lsof";
  version = "4.99.7";

  src = fetchurl {
    url = "https://github.com/lsof-org/lsof/releases/download/${finalAttrs.version}/lsof-${finalAttrs.version}.tar.gz";
    hash = "sha256-ShA5GqsLjOH1OegqGWZpOyps8iWXKmUE67fsT6cWdd4=";
  };

  nativeBuildInputs = [ groff ];

  # Bionic Porting Notes:
  # 1. Manpage Generation:
  #    groff provides soelim required by the Makefile to format Lsof.8 into lsof.man.
  # 2. Maximum File Descriptors (getdtablesize):
  #    Bionic omits legacy BSD getdtablesize(). We patch lib/proto.h to map GET_MAX_FD()
  #    directly to standard POSIX sysconf(_SC_OPEN_MAX).
  # 3. Dynamic Runtime & Page Alignment:
  #    Bionic stdenv automatically enforces 16 KB page alignment and relative $ORIGIN/../lib RUNPATH.
  postPatch = ''
    substituteInPlace lib/proto.h \
      --replace-fail '#        define GET_MAX_FD getdtablesize' '#        define GET_MAX_FD() sysconf(_SC_OPEN_MAX)'
  '';

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "List open files diagnostic utility for Android 14+ (Bionic libc)";
    homepage = "https://github.com/lsof-org/lsof";
    license = lib.licenses.purdueBsd or lib.licenses.lsof;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "lsof";
  };
})
