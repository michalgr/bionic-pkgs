# pkgs/libs/pcre2/default.nix
# PCRE2 regular expression library for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pcre2";
  version = "10.47";

  src = fetchurl {
    url = "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${finalAttrs.version}/pcre2-${finalAttrs.version}.tar.bz2";
    hash = "sha256-R/6MmUYSUNQviebo/a66naBXhV0G63/AjZygP9CNe8c=";
  };

  # Bionic Porting Notes:
  # 1. Disable JIT:
  #    Android W^X security policies restrict RWX memory page allocations required by PCRE2 JIT.
  # 2. Version Script Disablement:
  #    PCRE2 10.47 introduced a symbol version script that references undefined JIT symbols when JIT
  #    is disabled, as well as _init/_fini symbols absent in Bionic libc. LLVM lld rejects undefined
  #    symbols in version scripts by default. Disabling version scripts via ax_cv_check_vscript_flag
  #    allows clean linkage.
  configureFlags = [
    "--enable-pcre2-16"
    "--enable-pcre2-32"
    "--disable-jit"
    "ax_cv_check_vscript_flag=unsupported"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Perl Compatible Regular Expressions (v2) for Android 14+ (Bionic libc)";
    homepage = "https://www.pcre.org/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
