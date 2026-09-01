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
      directDeps = lib.filter (d: lib.isDerivation d && d ? outPath) (
        (pkg.buildInputs or [ ]) ++ (pkg.propagatedBuildInputs or [ ])
      );
      allDeps = lib.closePropagation directDeps;
      pushScript = hostPkgs.writeShellScriptBin "push-${pkgName}-${targetName}" ''
        set -euo pipefail
        exec ${../scripts}/adb-push.sh \
          --pkg-path "${pkg}" \
          --pkg-name "${pkgName}" \
          --target "${targetName}" \
          --bin-name "${binName}" \
          --adb "${adbBin}" \
          ${lib.concatMapStringsSep " " (dep: "--dep \"${dep.lib or dep.out or dep}\"") allDeps} \
          "$@"
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
    (pkg ? meta && pkg.meta ? mainProgram);

  # Helper to determine if a package can be verified for ELF properties (excluding header/shim/prebuilt-only packages)
  isCheckablePkg = pkg:
    lib.isDerivation pkg &&
    !(pkg.meta.skipElfCheck or false) &&
    (pkg ? pname);

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
      bash ${../scripts}/check-elf.sh "${pkg}" "${targetName}" "${pkgName}" "$out"
    '';

  # Automatically generates checks for all target matrix packages
  generateChecks = { hostPkgs, targetMatrix }:
    let
      checkEntries = lib.concatMap (targetName:
        let pkgsForTarget = targetMatrix.${targetName};
        in lib.concatMap (pkgName:
          let pkg = pkgsForTarget.${pkgName};
          in lib.optional (isCheckablePkg pkg) {
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
