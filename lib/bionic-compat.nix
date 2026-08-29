# lib/bionic-compat.nix
# Bionic libc compatibility overlay, compilation flags, and stdenv patches for Android targets.

{ lib }:

let
  fixLlvmPackages = { bionicFlags, final }: lfinal: lprev: {
    compiler-rt-no-libc = lprev.compiler-rt-no-libc.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [
        final.bionic.dev
        final.bionic.out
        final.bionic-compat
      ];
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = bionicFlags.cflagsString + " " + (old.env.NIX_CFLAGS_COMPILE or "");
        NIX_CFLAGS_LINK = bionicFlags.ldflagsString + " " + (old.env.NIX_CFLAGS_LINK or "");
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
        final.bionic-compat
      ];
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = bionicFlags.cflagsString + " " + (old.env.NIX_CFLAGS_COMPILE or "");
        NIX_CFLAGS_LINK = bionicFlags.ldflagsString + " " + (old.env.NIX_CFLAGS_LINK or "");
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
        final.bionic-compat
      ];
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = bionicFlags.cflagsString + " " + (old.env.NIX_CFLAGS_COMPILE or "");
        NIX_CFLAGS_LINK = bionicFlags.ldflagsString + " " + (old.env.NIX_CFLAGS_LINK or "");
      };
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        (lib.cmakeFeature "LIBCXXABI_ADDITIONAL_LIBRARIES" "unwind")
      ];
    });

    libllvm = lprev.libllvm.overrideAttrs (old: {
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
        "-DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON"
        "-DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON"
        "-DLLVM_TARGETS_TO_BUILD=BPF;AArch64;X86;ARM"
        "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=sha1"
        "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,--build-id=sha1"
        "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--build-id=sha1"
      ];
    });

    llvm = lfinal.libllvm;

    libclang = lprev.libclang.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [
        lfinal.libcxx
      ];
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        "-DLLVM_ENABLE_LIBCXX=ON"
        "-DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON"
        "-DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON"
        "-DLLVM_TARGETS_TO_BUILD=BPF;AArch64;X86;ARM"
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
      # Priority header search paths for Bionic compat shims and Bionic libc headers
      "-idirafter ${final.bionic-compat}/include"
      "-idirafter ${final.android-prebuilts}/include"
      # Enforce native ELF Thread-Local Storage (TLS) instead of emulated TLS
      "-fno-emulated-tls"
      # Modern Android (Android 15+) dynamic page size support
      "-D__BIONIC_NO_PAGE_SIZE_MACRO"
    ];
    ldflags = [
      # Library search paths for GNU Linker Script shims and Bionic libc
      "-L${final.bionic-compat}/lib"
      "-L${final.bionic.out}/lib"
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

  bionic-compat = final.callPackage ../pkgs/libs/bionic-compat { };
  android-prebuilts = final.callPackage ../pkgs/libs/android-prebuilts { };

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

  # ncurses for cross-compilation on Bionic
  ncurses = prev.ncurses.overrideAttrs (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [
      "--without-cxx-binding"
      "--without-ada"
    ];
  });

  llvmPackages = prev.llvmPackages.overrideScope (fixLlvmPackages { inherit bionicFlags final; });
}
// (lib.optionalAttrs (prev ? llvmPackages_21) {
  llvmPackages_21 = prev.llvmPackages_21.overrideScope (fixLlvmPackages { inherit bionicFlags final; });
})
// {
  # Setup hook that injects Bionic compiler/linker flags, header priority, and rewrites ELF RUNPATH
  bionicFixupHook = final.makeSetupHook {
    name = "bionic-fixup-hook";
    propagatedBuildInputs = [ final.bionic-compat ];
  } (final.writeScript "bionic-fixup.sh" ''
    # Export canonical compilation and linker flags into environment at setup hook source time
    export NIX_CFLAGS_COMPILE_${final.stdenv.cc.suffixSalt}="${bionicFlags.cflagsString} ''${NIX_CFLAGS_COMPILE_${final.stdenv.cc.suffixSalt}:-}"
    export NIX_LDFLAGS_${final.stdenv.cc.suffixSalt}="${bionicFlags.ldflagsString} ''${NIX_LDFLAGS_${final.stdenv.cc.suffixSalt}:-}"

    bionicFixup() {
      for output in ''${outputs:-out}; do
        local dir="''${!output:-}"
        if [ -n "$dir" ] && [ -d "$dir" ]; then
          find "$dir" -type f \( -perm -0100 -o -name "*.so*" \) -print0 | while IFS= read -r -d "" elf; do
            if [ -f "$elf" ] && [ "$(od -An -N4 -tx1 "$elf" 2>/dev/null | tr -d ' \n')" = "7f454c46" ]; then
              chmod +w "$elf" 2>/dev/null || true
              ${final.buildPackages.patchelf}/bin/patchelf --set-rpath '$ORIGIN/../lib:$ORIGIN/lib' "$elf" 2>/dev/null || true
            fi
          done
        fi
      done
    }
    postFixupHooks+=(bionicFixup)
  '');

  # Automatically equip target stdenv with Bionic flags, compatibility shims, and postFixup RPATH hook
  stdenv = prev.stdenv.override (old: {
    extraNativeBuildInputs = (old.extraNativeBuildInputs or [ ]) ++ [ final.bionicFixupHook ];
  });
}
