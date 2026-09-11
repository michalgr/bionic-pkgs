# pkgs/libs/llvm/src.nix
# Source derivation for LLVM 19.1.7 release tarball.

{ fetchurl }:

rec {
  version = "19.1.7";
  src = fetchurl {
    url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-${version}/llvm-project-${version}.src.tar.xz";
    hash = "sha256-gkAf6nt50AeAQ/dZi4NShNZlCnW5PmS292Hqe2MJdQE=";
  };
}
