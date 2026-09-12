# lib/overlays/llvm.nix
# LLVM toolchain scope overrides for target C++ runtime libraries on Android Bionic targets.

{ lib }:

final: prev:
let
  bionicFlags = final.bionicFlags;

  fixLlvm =
    lfinal: lprev:
    let
      withBionic =
        drv: attrsFn:
        drv.overrideAttrs (
          old:
          let
            extra = attrsFn old;
          in
          extra
          // {
            buildInputs =
              (old.buildInputs or [ ])
              ++ [
                final.bionic.dev
                final.bionic.out
              ]
              ++ (extra.buildInputs or [ ]);
            env =
              (old.env or { })
              // {
                NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " " + bionicFlags.cflagsString;
              }
              // (extra.env or { });
          }
        );
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
      });
    };
in
{
  llvmPackages = prev.llvmPackages.overrideScope fixLlvm;
}
// lib.optionalAttrs (prev ? llvmPackages_21) {
  llvmPackages_21 = prev.llvmPackages_21.overrideScope fixLlvm;
}
