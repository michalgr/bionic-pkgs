# lib/bionic-compat.nix
# Bionic libc compatibility overlay, compilation flags, and stdenv patches for Android targets.

{ lib }:

let
  fixLlvmPackages = { bionicFlags, final }: lfinal: lprev: {
    compiler-rt-no-libc = lprev.compiler-rt-no-libc.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [
        final.bionic.dev
        final.bionic.out
      ];
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " " + bionicFlags.cflagsString;
      };
      postInstall = ''
        mkdir -p $out/lib
        for f in $out/lib/*/*.a; do
          if [ -f "$f" ]; then
            ln -sf "$f" "$out/lib/$(basename "$f")"
          fi
        done
      '';
    });

    compiler-rt-libc = lfinal.compiler-rt-no-libc;
    compiler-rt = lfinal.compiler-rt-no-libc;

    libunwind = lprev.libunwind.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [
        final.bionic.dev
        final.bionic.out
      ];
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " " + bionicFlags.cflagsString;
      };
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
        "-DLIBUNWIND_ENABLE_SHARED=OFF"
        "-DLIBUNWIND_ENABLE_STATIC=ON"
      ];
      postInstall = ''
        ln -sf $out/lib/libunwind.a $out/lib/libgcc_s.a || true
      '';
    });

    libcxx = lprev.libcxx.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [
        final.bionic.dev
        final.bionic.out
      ];
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " " + bionicFlags.cflagsString;
        NIX_LDFLAGS = (old.env.NIX_LDFLAGS or "") + " " + bionicFlags.ldflagsString;
      };
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        (lib.cmakeFeature "LIBCXXABI_ADDITIONAL_LIBRARIES" "unwind")
      ];
      postInstall = (old.postInstall or "") + ''
        ln -sf libc++.so $out/lib/libc++_shared.so
        ln -sf libc++.a $out/lib/libc++_static.a
      '';
    });

    libllvm = (lprev.libllvm.override { libxml2 = null; }).overrideAttrs (old: {
      propagatedBuildInputs = lib.filter (p: !(lib.hasInfix "ncurses" (p.name or ""))) (old.propagatedBuildInputs or [ ]);
      buildInputs = (old.buildInputs or [ ]) ++ [
        lfinal.libcxx
      ];
      # Nixpkgs unconditionally sets env.LDFLAGS = "-Wl,--build-id=sha1" when stdenv.hostPlatform is not Darwin.
      # When cross-compiling on a Darwin host (macOS), LLVM's nested NATIVE subproject for tablegen tools
      # inherits this ambient LDFLAGS environment variable, causing Darwin ld to fail with:
      # "ld: unknown option: --build-id=sha1".
      # We clear ambient LDFLAGS from the derivation environment and pass build-id explicitly via cmakeFlags for the target.
      env = (old.env or { }) // {
        LDFLAGS = "";
      };
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        "-DLLVM_ENABLE_LIBCXX=ON"
        "-DLLVM_ENABLE_TERMINFO=OFF"
        "-DLLVM_ENABLE_LIBXML2=OFF"
        "-DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON"
        "-DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON"
        "-DLLVM_TARGETS_TO_BUILD=BPF;AArch64;X86;ARM"
        "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=sha1"
        "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,--build-id=sha1"
        "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--build-id=sha1"
      ];
    });

    llvm = lfinal.libllvm;

    libclang = (lprev.libclang.override { libxml2 = null; }).overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [
        lfinal.libcxx
      ];
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        "-DLLVM_ENABLE_LIBCXX=ON"
        "-DLLVM_ENABLE_LIBXML2=OFF"
        "-DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON"
        "-DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON"
        "-DLLVM_TARGETS_TO_BUILD=BPF;AArch64;X86;ARM"
        "-DLIBCLANG_BUILD_STATIC=ON"
      ];
    });

    clang-unwrapped = lfinal.libclang;
  };
in
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
      # Android 15+ 16 KB memory page alignment for ELF LOAD segments
      "-z" "max-page-size=16384"
      "-z" "common-page-size=16384"
      # Pure Link-Time RPATH emission for Android dynamic linker
      "-rpath" "\\$ORIGIN/../lib:\\$ORIGIN:\\$ORIGIN/..:\\$ORIGIN/../.."
      "--enable-new-dtags"
    ];
    cflagsString = lib.concatStringsSep " " cflags;
    ldflagsString = lib.concatStringsSep " " ldflags;
  };
in
{
  inherit bionicFlags;

  # Custom Android 14+ (API 34) Bionic libc & NDK r27 sysroot with built-in shims
  bionic = final.callPackage ../pkgs/libs/bionic { };

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

  llvmPackages = prev.llvmPackages.overrideScope (fixLlvmPackages { inherit bionicFlags final; });
}
// (lib.optionalAttrs (prev ? llvmPackages_21) {
  llvmPackages_21 = prev.llvmPackages_21.overrideScope (fixLlvmPackages { inherit bionicFlags final; });
})
// {
  # Setup hook that injects Bionic compiler/linker flags and suppresses Nixpkgs auto-RPATH & patchelf fixups
  bionicFixupHook = final.makeSetupHook {
    name = "bionic-fixup-hook";
  } (final.writeScript "bionic-fixup.sh" ''
    # Export canonical compilation and linker flags into environment at setup hook source time
    export NIX_CFLAGS_COMPILE_${final.stdenv.cc.suffixSalt}="${bionicFlags.cflagsString} ''${NIX_CFLAGS_COMPILE_${final.stdenv.cc.suffixSalt}:-}"
    export NIX_LDFLAGS_${final.stdenv.cc.suffixSalt}="${bionicFlags.ldflagsString} ''${NIX_LDFLAGS_${final.stdenv.cc.suffixSalt}:-}"

    # Suppress Nixpkgs automatic RPATH generation and post-link patchelf fixups to preserve pure link-time RPATHs
    export NIX_DONT_SET_RPATH=1
    export NIX_DONT_SET_RPATH_FOR_TARGET=1
    export NIX_DONT_SET_RPATH_${final.stdenv.cc.suffixSalt}=1
    export NIX_NO_SET_RPATH=1
    export NIX_NO_SET_RPATH_FOR_TARGET=1
    export NIX_NO_SET_RPATH_${final.stdenv.cc.suffixSalt}=1
    export dontPatchELF=1
    export dontShrinkRPATH=1

    # Prevent CMake from adding $out/lib to RPATH during cmake install
    export CMAKE_SKIP_INSTALL_RPATH=ON

    # Prevent libtool from hardcoding $out/lib into binary RPATH during make install
    bionicFixupLibtool() {
      if [ -f libtool ]; then
        substituteInPlace libtool \
          --replace-warn 'hardcode_libdir_flag_spec="''${wl}-rpath ''${wl}$libdir"' 'hardcode_libdir_flag_spec=""' \
          --replace-warn 'hardcode_libdir_flag_spec_CXX="''${wl}-rpath ''${wl}$libdir"' 'hardcode_libdir_flag_spec_CXX=""' || true
      fi
    }
    postConfigureHooks+=(bionicFixupLibtool)
  '');

  # Automatically equip target stdenv with Bionic flags and setup hook
  stdenv = prev.stdenv.override (old: {
    extraNativeBuildInputs = (old.extraNativeBuildInputs or [ ]) ++ [ final.bionicFixupHook ];
  });
}
