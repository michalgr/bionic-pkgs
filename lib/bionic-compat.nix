# lib/bionic-compat.nix
# Bionic libc compatibility overlay and stdenv patches for Android targets.

{ lib }:

let
  fixLlvmPackages = lfinal: lprev: final: {
    compiler-rt-no-libc = lprev.compiler-rt-no-libc.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [
        final.bionic.dev
        final.bionic.out
        final.bionic-compat
      ];
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -isystem ${final.bionic-compat}/include -isystem ${final.bionic.dev}/include -fno-emulated-tls";
        NIX_CFLAGS_LINK = (old.env.NIX_CFLAGS_LINK or "") + " -L${final.bionic-compat}/lib -L${final.bionic.out}/lib";
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
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -isystem ${final.bionic-compat}/include -isystem ${final.bionic.dev}/include -fno-emulated-tls";
        NIX_CFLAGS_LINK = (old.env.NIX_CFLAGS_LINK or "") + " -L${final.bionic-compat}/lib -L${final.bionic.out}/lib";
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
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -isystem ${final.bionic-compat}/include -isystem ${final.bionic.dev}/include -fno-emulated-tls";
        NIX_CFLAGS_LINK = (old.env.NIX_CFLAGS_LINK or "") + " -L${final.bionic-compat}/lib -L${final.bionic.out}/lib";
      };
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        (lib.cmakeFeature "LIBCXXABI_ADDITIONAL_LIBRARIES" "unwind")
      ];
    });

    clang = lprev.clang.override (old: {
      extraBuildCommands = (old.extraBuildCommands or "") + ''
        if [ -f "$out/nix-support/libc-cflags" ]; then
          substituteInPlace "$out/nix-support/libc-cflags" --replace-warn "-idirafter" "-isystem"
          sed -i '1s,^,-isystem ${final.bionic-compat}/include ,' "$out/nix-support/libc-cflags"
        fi
        # Enforce native ELF TLS and 16 KB page alignment for all derivations
        echo "-fno-emulated-tls" >> "$out/nix-support/cc-cflags"
        echo "-L${final.bionic-compat}/lib -z max-page-size=16384 -z common-page-size=16384" >> "$out/nix-support/cc-ldflags"
      '';
    });
  };
in
final: prev: {
  bionic-compat = final.callPackage ../pkgs/libs/bionic-compat { };

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

  llvmPackages = prev.llvmPackages.overrideScope (lfinal: lprev: fixLlvmPackages lfinal lprev final);
  llvmPackages_21 = prev.llvmPackages_21.overrideScope (lfinal: lprev: fixLlvmPackages lfinal lprev final);

  # Setup hook that ensures Bionic header priority, 16 KB page alignment, and rewrites ELF RUNPATH
  bionicFixupHook = final.makeSetupHook {
    name = "bionic-fixup-hook";
    propagatedBuildInputs = [ final.bionic-compat ];
  } (final.writeScript "bionic-fixup.sh" ''
    bionicPreConfigure() {
      export NIX_CFLAGS_COMPILE="-isystem ${final.bionic-compat}/include -isystem ${final.bionic.dev}/include -fno-emulated-tls ''${NIX_CFLAGS_COMPILE:-}"
      export NIX_LDFLAGS="-L${final.bionic-compat}/lib -z max-page-size=16384 -z common-page-size=16384 ''${NIX_LDFLAGS:-}"
    }
    preConfigureHooks+=(bionicPreConfigure)

    bionicFixup() {
      for output in "''${outputs[@]:-out}"; do
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
}
