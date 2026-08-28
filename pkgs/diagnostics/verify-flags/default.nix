{ stdenv, lib }:

stdenv.mkDerivation {
  pname = "verify-flags";
  version = "1.0.0";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out

    echo "=== NIX ENVIRONMENT VARIABLES ===" > $out/flags.log
    env | grep -E '^NIX_(CFLAGS_COMPILE|LDFLAGS)_' | sort >> $out/flags.log || true
    env | grep -E '^(NIX_CFLAGS_COMPILE|NIX_LDFLAGS|CFLAGS|CXXFLAGS|LDFLAGS)=' | sort >> $out/flags.log || true

    echo "" >> $out/flags.log
    echo "=== CLANG INVOCATION (DRY RUN) ===" >> $out/flags.log

    echo "int main() { return 0; }" > dummy.c

    # We use -### to just print the invocation commands without executing them
    $CC -### dummy.c -o dummy 2>> $out/flags.log || true
  '';

  installPhase = ''
    # Output is already in $out from buildPhase
  '';

  meta = with lib; {
    description = "Utility package to verify clang flags and environment variables";
    platforms = platforms.all;
    license = licenses.mit;
  };
}
