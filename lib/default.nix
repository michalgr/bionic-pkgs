# lib/default.nix
# Target platform matrix and build helper utilities for bionic-pkgs.

{ lib }:

let
  # Primary 64-bit Android targets supported on Android 14+
  targetPlatforms = {
    aarch64-android = {
      config = "aarch64-unknown-linux-android";
      androidSdkVersion = "34";
      useLLVM = true;
    };
    x86_64-android = {
      config = "x86_64-unknown-linux-android";
      androidSdkVersion = "34";
      useLLVM = true;
    };
  };

  supportedTargets = builtins.attrNames targetPlatforms;
  defaultTarget = "aarch64-android";

  supportedSystems = [
    "aarch64-linux"
    "x86_64-linux"
    "aarch64-darwin"
  ];

  # Helper to instantiate nixpkgs with Bionic cross-compilation overlays
  mkAndroidPkgs = { nixpkgs, system, targetName }:
    let
      bionicCompat = import ./bionic-compat.nix { inherit lib; };
      crossSystem = targetPlatforms.${targetName};
    in
    import nixpkgs {
      localSystem = { inherit system; };
      inherit crossSystem;
      crossOverlays = [ bionicCompat ];
    };

  # Helper to create an ADB deployment app that synchronizes binary and shared libraries
  mkAdbPushApp = { hostPkgs, pkg, targetName, pkgName }:
    let
      adbBin = "${hostPkgs.android-tools}/bin/adb";
      binName = if pkg ? meta && pkg.meta ? mainProgram then pkg.meta.mainProgram else pkgName;
      pushScript = hostPkgs.writeShellScriptBin "push-${pkgName}-${targetName}" ''
        set -euo pipefail
        shopt -s nullglob

        DEST_DIR="/data/local/tmp/bionic-pkgs/${pkgName}"
        echo "==> Preparing ${pkgName} for target ${targetName}..."
        echo "==> Target device staging directory: $DEST_DIR"

        ADB_CMD="${adbBin}"
        if ! command -v "$ADB_CMD" >/dev/null 2>&1; then
          if command -v adb >/dev/null 2>&1; then
            ADB_CMD="adb"
          else
            echo "Error: adb command not found." >&2
            exit 1
          fi
        fi

        ADB_FLAGS=()
        if [ -n "''${ANDROID_SERIAL:-''${ADB_SERIAL:-}}" ]; then
          ADB_FLAGS+=(-s "''${ANDROID_SERIAL:-''${ADB_SERIAL}}")
        fi

        run_adb() {
          "$ADB_CMD" "''${ADB_FLAGS[@]}" "$@"
        }

        echo "==> Creating remote directory structure on device..."
        run_adb shell "mkdir -p $DEST_DIR/bin $DEST_DIR/lib"

        echo "==> Pushing binaries..."
        if [ -d "${pkg}/bin" ]; then
          bin_files=("${pkg}"/bin/*)
          if [ ''${#bin_files[@]} -gt 0 ]; then
            for f in "''${bin_files[@]}"; do
              if [ -f "$f" ]; then
                run_adb push "$f" "$DEST_DIR/bin/"
              fi
            done
            run_adb shell "chmod 755 $DEST_DIR/bin/* 2>/dev/null || true"
          fi
        fi

        echo "==> Pushing shared libraries and closure..."
        if [ -d "${pkg}/lib" ]; then
          lib_files=("${pkg}"/lib/*)
          if [ ''${#lib_files[@]} -gt 0 ]; then
            for f in "''${lib_files[@]}"; do
              if [ -f "$f" ]; then
                run_adb push "$f" "$DEST_DIR/lib/"
              fi
            done
          fi
        fi

        # Push dynamic library dependencies from closure if present
        closure_paths=$(nix-store -qR "${pkg}" 2>/dev/null || true)
        if [ -n "$closure_paths" ]; then
          for req in $closure_paths; do
            if [ "$req" != "${pkg}" ] && [ -d "$req/lib" ]; then
              for f in "$req"/lib/*.so*; do
                if [ -f "$f" ]; then
                  run_adb push "$f" "$DEST_DIR/lib/" 2>/dev/null || true
                fi
              done
            fi
          done
        fi

        # Deploy launcher wrapper script with LD_LIBRARY_PATH support
        LAUNCHER=$(mktemp "/tmp/bionic_run_${pkgName}_XXXXXX.sh")
        cat << 'EOF' > "$LAUNCHER"
#!/system/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$SCRIPT_DIR/../lib:$LD_LIBRARY_PATH"
if [ -x "$SCRIPT_DIR/bin/${binName}" ]; then
  exec "$SCRIPT_DIR/bin/${binName}" "$@"
else
  echo "Executable $SCRIPT_DIR/bin/${binName} not found" >&2
  exit 1
fi
EOF
        run_adb push "$LAUNCHER" "$DEST_DIR/run.sh" >/dev/null
        rm -f "$LAUNCHER"
        run_adb shell "chmod 755 $DEST_DIR/run.sh"

        echo ""
        echo "==> Deployment complete!"
        echo "==> Run on device via ADB:"
        echo "    adb shell \"$DEST_DIR/run.sh\""
        echo "    # Or directly:"
        echo "    adb shell \"$DEST_DIR/bin/${binName}\""
      '';
    in
    {
      type = "app";
      program = "${pushScript}/bin/push-${pkgName}-${targetName}";
      meta = {
        description = "Push ${pkgName} and its runtime dependencies to an Android device via ADB";
        mainProgram = "push-${pkgName}-${targetName}";
      };
    };

  # Evaluates packages for all target architectures
  mkTargetMatrix = { nixpkgs, system, packageSetFn }:
    builtins.listToAttrs (map (targetName: {
      name = targetName;
      value = packageSetFn {
        targetPkgs = mkAndroidPkgs { inherit nixpkgs system targetName; };
      };
    }) supportedTargets);

  # Helper to determine if a package is a runnable application
  isRunnableApp = pkg:
    lib.isDerivation pkg &&
    ((pkg ? meta && pkg.meta ? mainProgram) ||
     (pkg ? pname && pkg.pname != "bionic-compat"));

  # Automatically generates flat package outputs from targetMatrix
  generatePackages = { targetMatrix, defaultTarget ? "aarch64-android" }:
    let
      targetEntries = lib.concatMap (targetName:
        let pkgsForTarget = targetMatrix.${targetName};
        in map (pkgName: {
          name = "${targetName}-${pkgName}";
          value = pkgsForTarget.${pkgName};
        }) (builtins.attrNames pkgsForTarget)
      ) (builtins.attrNames targetMatrix);

      defaultEntries = if targetMatrix ? ${defaultTarget} then
        map (pkgName: {
          name = pkgName;
          value = targetMatrix.${defaultTarget}.${pkgName};
        }) (builtins.attrNames targetMatrix.${defaultTarget})
      else [ ];

      defaultPackage = if targetMatrix ? ${defaultTarget} && targetMatrix.${defaultTarget} ? strace
        then { default = targetMatrix.${defaultTarget}.strace; }
        else { };
    in
    builtins.listToAttrs (targetEntries ++ defaultEntries) // defaultPackage;

  # Automatically generates ADB push apps from targetMatrix
  generateApps = { hostPkgs, targetMatrix, defaultTarget ? "aarch64-android" }:
    let
      targetAppEntries = lib.concatMap (targetName:
        let pkgsForTarget = targetMatrix.${targetName};
        in lib.concatMap (pkgName:
          let pkg = pkgsForTarget.${pkgName};
          in lib.optional (isRunnableApp pkg) {
            name = "push-${targetName}-${pkgName}";
            value = mkAdbPushApp {
              inherit hostPkgs targetName pkgName pkg;
            };
          }
        ) (builtins.attrNames pkgsForTarget)
      ) (builtins.attrNames targetMatrix);

      defaultAppEntries = if targetMatrix ? ${defaultTarget} then
        lib.concatMap (pkgName:
          let pkg = targetMatrix.${defaultTarget}.${pkgName};
          in lib.optional (isRunnableApp pkg) {
            name = "push-${pkgName}";
            value = mkAdbPushApp {
              inherit hostPkgs pkgName pkg;
              targetName = defaultTarget;
            };
          }
        ) (builtins.attrNames targetMatrix.${defaultTarget})
      else [ ];

      defaultApp = if targetMatrix ? ${defaultTarget} && targetMatrix.${defaultTarget} ? strace
        then {
          default = mkAdbPushApp {
            inherit hostPkgs;
            targetName = defaultTarget;
            pkgName = "strace";
            pkg = targetMatrix.${defaultTarget}.strace;
          };
        }
        else { };
    in
    builtins.listToAttrs (targetAppEntries ++ defaultAppEntries) // defaultApp;

  # Helper to create an ELF verification check derivation for CI / nix flake check
  mkElfCheck = { hostPkgs, pkg, targetName, pkgName }:
    hostPkgs.runCommand "check-elf-${pkgName}-${targetName}" {
      nativeBuildInputs = [
        hostPkgs.llvmPackages.llvm
        hostPkgs.file
      ];
    } ''
      set -euo pipefail
      echo "==> Verifying ELF properties for ${pkgName} (${targetName})..."

      found_elf=0
      mapfile -t elf_files < <(find "${pkg}" -type f)

      for elf_file in "''${elf_files[@]}"; do
        if [ -f "$elf_file" ] && [ "$(od -An -N4 -tx1 "$elf_file" 2>/dev/null | tr -d ' \n')" = "7f454c46" ]; then
          found_elf=$((found_elf + 1))
          rel_path="''${elf_file#${pkg}/}"
          echo "--- Checking ELF artifact: $rel_path ---"
          file "$elf_file"

          # 1. Verify Target Architecture / Machine Header
          machine=$(llvm-readelf -h "$elf_file" 2>/dev/null | awk -F: '/Machine:/ {print $2}' | xargs || true)
          echo "ELF Machine: $machine"
          case "${targetName}" in
            aarch64-android)
              if [ "$machine" != "AArch64" ]; then
                echo "ERROR: Expected AArch64 machine, got: $machine" >&2
                exit 1
              fi
              ;;
            x86_64-android)
              if [ "$machine" != "Advanced Micro Devices X86-64" ]; then
                echo "ERROR: Expected Advanced Micro Devices X86-64 machine, got: $machine" >&2
                exit 1
              fi
              ;;
            armv7a-android)
              if [ "$machine" != "ARM" ]; then
                echo "ERROR: Expected ARM machine, got: $machine" >&2
                exit 1
              fi
              ;;
            i686-android)
              if [ "$machine" != "Intel 80386" ]; then
                echo "ERROR: Expected Intel 80386 machine, got: $machine" >&2
                exit 1
              fi
              ;;
          esac

          # 2. Check Dynamic Linker Interpreter (for executables)
          interp=$(llvm-readelf -l "$elf_file" 2>/dev/null | grep 'program interpreter' | tr -d '[]' | awk '{print $NF}' || true)
          case "$rel_path" in
            bin/*|sbin/*|libexec/*)
              if [ -n "$interp" ]; then
                echo "Dynamic interpreter: $interp"
                case "${targetName}" in
                  aarch64-android|x86_64-android)
                    if [ "$interp" != "/system/bin/linker64" ]; then
                      echo "ERROR: Expected 64-bit dynamic linker /system/bin/linker64, got $interp" >&2
                      exit 1
                    fi
                    ;;
                  armv7a-android|i686-android)
                    if [ "$interp" != "/system/bin/linker" ]; then
                      echo "ERROR: Expected 32-bit dynamic linker /system/bin/linker, got $interp" >&2
                      exit 1
                    fi
                    ;;
                esac
              fi
              ;;
          esac

          # 3. Check 16 KB Page Alignment on LOAD segments
          echo "Checking LOAD segment alignments..."
          load_count=0
          for align in $(llvm-readelf -l "$elf_file" | awk '$1 == "LOAD" {print $NF}'); do
            load_count=$((load_count + 1))
            align_dec=$((align))
            if [ "$align_dec" -lt 16384 ]; then
              echo "ERROR: LOAD segment alignment $align ($align_dec bytes) is less than 16 KB (16384 bytes) in $rel_path" >&2
              exit 1
            fi
          done
          if [ "$load_count" -eq 0 ]; then
            echo "ERROR: No LOAD segments found in $rel_path" >&2
            exit 1
          fi

          # 4. Check Forbidden glibc dependencies
          for forbidden in libpthread.so librt.so libutil.so libresolv.so libcrypt.so libnsl.so libanl.so libc.so.6 libm.so.6 ld-linux; do
            if llvm-readelf -d "$elf_file" 2>/dev/null | grep NEEDED | grep -q "$forbidden"; then
              echo "ERROR: Binary links forbidden glibc library: $forbidden" >&2
              exit 1
            fi
          done

          # 5. Check Relative RUNPATH ($ORIGIN/...)
          rpath=$(llvm-readelf -d "$elf_file" 2>/dev/null | grep RUNPATH || true)
          if [ -n "$rpath" ]; then
            echo "RUNPATH: $rpath"
            if echo "$rpath" | grep -q "/nix/store"; then
              echo "ERROR: Binary RUNPATH contains host /nix/store path!" >&2
              exit 1
            fi
          fi
        fi
      done

      if [ "$found_elf" -eq 0 ]; then
        echo "ERROR: No ELF binaries or libraries found in ${pkg}" >&2
        exit 1
      fi

      echo "==> Successfully verified $found_elf ELF artifact(s) for ${pkgName} (${targetName})."
      mkdir -p "$out"
      echo "ELF verification passed for ${pkgName} (${targetName}) ($found_elf artifacts)" > "$out/result"
    '';

  # Automatically generates checks for all target matrix packages
  generateChecks = { hostPkgs, targetMatrix }:
    let
      checkEntries = lib.concatMap (targetName:
        let pkgsForTarget = targetMatrix.${targetName};
        in lib.concatMap (pkgName:
          let pkg = pkgsForTarget.${pkgName};
          in lib.optional (isRunnableApp pkg) {
            name = "check-elf-${targetName}-${pkgName}";
            value = mkElfCheck {
              inherit hostPkgs targetName pkgName pkg;
            };
          }
        ) (builtins.attrNames pkgsForTarget)
      ) (builtins.attrNames targetMatrix);
    in
    builtins.listToAttrs checkEntries;

in
{
  inherit
    targetPlatforms
    supportedTargets
    defaultTarget
    supportedSystems
    mkAndroidPkgs
    mkAdbPushApp
    mkElfCheck
    mkTargetMatrix
    generatePackages
    generateApps
    generateChecks;
}
