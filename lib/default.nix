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

in
{
  inherit
    targetPlatforms
    supportedTargets
    defaultTarget
    supportedSystems
    mkAndroidPkgs
    mkAdbPushApp
    mkTargetMatrix
    generatePackages
    generateApps;
}
