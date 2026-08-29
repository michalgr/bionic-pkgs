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
    echo "int main() { return 0; }" > dummy.cpp

    # We use -### to just print the invocation commands without executing them
    echo "--- C ---" >> $out/flags.log
    $CC -### dummy.c -o dummy_c 2>> $out/flags.log || true

    echo "--- C++ ---" >> $out/flags.log
    $CXX -### dummy.cpp -o dummy_cpp 2>> $out/flags.log || true
  '';

  installPhase = ''
    # Output is already in $out from buildPhase
  '';

  meta = with lib; {
    description = "Utility package to verify clang flags and environment variables";
    platforms = platforms.all;
    license = licenses.mit;
    skipElfCheck = true;
  };
}
