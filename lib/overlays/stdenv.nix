# lib/overlays/stdenv.nix
# Compilation flags, setup hooks, and stdenv overrides for Android Bionic targets.

{ lib }:

final: prev:
let
  # Canonical compilation and linker flags for Android Bionic targets
  bionicFlags = rec {
    cflags = [
      # Prevent Clang from searching host C library include paths (/usr/include, /usr/local/include)
      "-nostdlibinc"
      # Enforce native ELF Thread-Local Storage (TLS) instead of emulated TLS
      "-fno-emulated-tls"
      # Modern Android (Android 15+) dynamic page size support
      "-D__BIONIC_NO_PAGE_SIZE_MACRO"
    ] ++ lib.optionals final.stdenv.hostPlatform.isx86_64 [
      # Disable TLSDESC on x86_64 because Android < 15 emulator (API 34) does not support R_X86_64_TLSDESC (36)
      "-mtls-dialect=gnu"
    ];
    ldflags = [
      # Library search path for Bionic libc and linker script stubs
      "-L${final.bionic.out}/lib"
      "-rpath" "\\$ORIGIN/../lib"
      # Android 15+ 16 KB memory page alignment for ELF LOAD segments
      "-z" "max-page-size=16384"
      "-z" "common-page-size=16384"
    ];
    cflagsString = lib.concatStringsSep " " cflags;
    ldflagsString = lib.concatStringsSep " " ldflags;
  };
in
{
  inherit bionicFlags;

  # Setup hook that injects Bionic compiler/linker flags and configures RPATH variables
  bionicFixupHook = final.makeSetupHook {
    name = "bionic-fixup-hook";
  } (final.writeScript "bionic-fixup.sh" ''
    # Export canonical compilation and linker flags into environment at setup hook source time
    export NIX_CFLAGS_COMPILE="${bionicFlags.cflagsString} ''${NIX_CFLAGS_COMPILE:-}"
    export NIX_LDFLAGS="${bionicFlags.ldflagsString} ''${NIX_LDFLAGS:-}"

    # Suppress Nixpkgs automatic RPATH generation and self-rpath injection
    export NIX_DONT_SET_RPATH=1
    export NIX_NO_SELF_RPATH=1
    export dontPatchELF=1
    export dontShrinkRPATH=1

    # Prevent CMake from injecting build-tree RPATHs or performing install-time RPATH rewrites
    addCmakeSkipRpath() {
      cmakeFlagsArray+=("-DCMAKE_SKIP_RPATH=ON")
    }
    preConfigureHooks+=(addCmakeSkipRpath)

    # Prevent Libtool from hardcoding $out/lib into RPATH during linking
    patchLibtoolRpath() {
      find . -name "libtool" -type f | while IFS= read -r lt; do
        if [ -f "$lt" ]; then
          sed -i 's/hardcode_libdir_flag_spec=.*/hardcode_libdir_flag_spec=""/g' "$lt"
          sed -i 's/hardcode_libdir_flag_spec_CXX=.*/hardcode_libdir_flag_spec_CXX=""/g' "$lt"
        fi
      done
    }
    postConfigureHooks+=(patchLibtoolRpath)
  '');

  # Automatically equip target stdenv with Bionic flags, compatibility shims, and postFixup RPATH hook
  stdenv = prev.stdenv.override (old: {
    extraNativeBuildInputs = (old.extraNativeBuildInputs or [ ]) ++ [ final.bionicFixupHook ];
  });
}
