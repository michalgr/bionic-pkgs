# lib/bionic-compat.nix
# Bionic libc compatibility overlay, compilation flags, and stdenv patches for Android targets.

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

  patchedLlvm = prev.llvmPackages.overrideScope (
    import ./llvm-compat.nix { inherit lib bionicFlags final; }
  );
in
{
  inherit bionicFlags;

  # Custom Android 14+ (API 34) Bionic libc & NDK r27 sysroot with built-in shims
  bionic = final.callPackage ./sysroot { };

  # Map zlib to Android platform NDK stubs so all packages bind directly to /system/lib64/libz.so
  zlib = final.bionic // {
    dev = final.bionic;
    out = final.bionic;
    static = final.bionic;
  };

  # Ensure Linux kernel headers build cleanly across all build hosts (including Darwin / macOS)
  makeLinuxHeaders = args:
    (prev.makeLinuxHeaders args).overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        # Disable building x86 kernel relocs utility during header generation on non-ELF/Darwin hosts
        if [ -f arch/x86/Makefile ]; then
          substituteInPlace arch/x86/Makefile \
            --replace-warn '$(Q)$(MAKE) $(build)=arch/x86/tools relocs' 'true' || true
        fi
      '';
      buildPhase = ''
        make headers $makeFlags
      '';
    });

  llvmPackages = patchedLlvm;

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
// lib.optionalAttrs (prev ? llvmPackages_21) {
  llvmPackages_21 = patchedLlvm;
}
