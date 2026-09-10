# lib/llvm-compat.nix
# LLVM toolchain scope overrides, runtime library patches, and compilation flags for Android Bionic targets.

{ lib }:

{ bionicFlags, final }:
lfinal: lprev:

let
  withBionic = drv: attrsFn:
    drv.overrideAttrs (old:
      let
        extra = attrsFn old;
      in
      extra // {
        buildInputs = (old.buildInputs or [ ]) ++ [
          final.bionic.dev
          final.bionic.out
        ] ++ (extra.buildInputs or [ ]);
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " " + bionicFlags.cflagsString;
        } // (extra.env or { });
      }
    );

  commonCmakeFlags = [
    "-DLLVM_ENABLE_LIBCXX=ON"
    "-DLLVM_ENABLE_LIBXML2=OFF"
    "-DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON"
    "-DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON"
    "-DLLVM_TARGETS_TO_BUILD=BPF;AArch64;X86;ARM"
  ];
in
{
  compiler-rt-no-libc = withBionic lprev.compiler-rt-no-libc (old: {
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

  libunwind = withBionic lprev.libunwind (old: {
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
      "-DLIBUNWIND_ENABLE_SHARED=OFF"
      "-DLIBUNWIND_ENABLE_STATIC=ON"
    ];
    postInstall = ''
      ln -sf $out/lib/libunwind.a $out/lib/libgcc_s.a || true
    '';
  });

  libcxx = withBionic lprev.libcxx (old: {
    env = {
      NIX_LDFLAGS = (old.env.NIX_LDFLAGS or "") + " " + bionicFlags.ldflagsString;
    };
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      (lib.cmakeFeature "LIBCXXABI_ADDITIONAL_LIBRARIES" "unwind")
      (lib.cmakeBool "LIBCXX_ENABLE_STATIC_ABI_LIBRARY" true)
    ];
    postInstall = (old.postInstall or "") + ''
      ln -sf libc++.so.1 $out/lib/libc++_shared.so
      ln -sf libc++.a $out/lib/libc++_static.a
    '';
    meta = (old.meta or { }) // { skipElfCheck = true; };
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
    cmakeFlags = (old.cmakeFlags or [ ]) ++ commonCmakeFlags ++ [
      "-DLLVM_ENABLE_TERMINFO=OFF"
      "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=sha1"
      "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,--build-id=sha1"
      "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--build-id=sha1"
    ];
    meta = (old.meta or { }) // { skipElfCheck = true; };
  });

  llvm = lfinal.libllvm;

  libclang = (lprev.libclang.override { libxml2 = null; }).overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [
      lfinal.libcxx
    ];
    cmakeFlags = (old.cmakeFlags or [ ]) ++ commonCmakeFlags ++ [
      "-DLIBCLANG_BUILD_STATIC=ON"
    ];
    meta = (old.meta or { }) // { skipElfCheck = true; };
  });

  clang-unwrapped = lfinal.libclang;
}
