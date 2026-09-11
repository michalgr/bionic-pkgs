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

  # Native helper to map outputs over supported host systems
  eachSystem = systems: f:
    let
      perSystem = lib.genAttrs systems f;
    in
    {
      packages = lib.mapAttrs (_: s: s.packages or { }) perSystem;
      legacyPackages = lib.mapAttrs (_: s: s.legacyPackages or { }) perSystem;
      apps = lib.mapAttrs (_: s: s.apps or { }) perSystem;
      checks = lib.mapAttrs (_: s: s.checks or { }) perSystem;
      devShells = lib.mapAttrs (_: s: s.devShells or { }) perSystem;
    };

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
  mkAdbPushApp = { hostPkgs, pkg, targetName, pkgName, targetMatrix }:
    let
      adbBin = "${hostPkgs.android-tools}/bin/adb";
      binName = if pkg ? meta && pkg.meta ? mainProgram then pkg.meta.mainProgram else pkgName;
      archivePkg = targetMatrix.${targetName}.runtimeArchive {
        pname = pkgName;
        packages = [ pkg ];
        launcherProgram = binName;
        launcherName = "run.sh";
        archiveName = "${pkgName}-${targetName}.tar.gz";
      };
      pushScript = hostPkgs.writeShellScriptBin "push-${pkgName}-${targetName}" ''
        set -euo pipefail
        exec ${../scripts}/adb-push.sh \
          --archive "${archivePkg}/${pkgName}-${targetName}.tar.gz" \
          --pkg-name "${pkgName}" \
          --target "${targetName}" \
          --bin-name "${binName}" \
          --adb "${adbBin}" \
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
        in lib.concatMap (pkgName:
          let pkg = pkgsForTarget.${pkgName};
          in lib.optional (lib.isDerivation pkg) {
            name = "${targetName}-${pkgName}";
            value = pkg;
          }
        ) (builtins.attrNames pkgsForTarget)
      ) (builtins.attrNames targetMatrix);

      defaultEntries = if targetMatrix ? ${defaultTarget} then
        lib.concatMap (pkgName:
          let pkg = targetMatrix.${defaultTarget}.${pkgName};
          in lib.optional (lib.isDerivation pkg) {
            name = pkgName;
            value = pkg;
          }
        ) (builtins.attrNames targetMatrix.${defaultTarget})
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
              inherit hostPkgs targetName pkgName pkg targetMatrix;
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
              inherit hostPkgs pkgName pkg targetMatrix;
              targetName = defaultTarget;
            };
          }
        ) (builtins.attrNames targetMatrix.${defaultTarget})
      else [ ];

      defaultApp = if targetMatrix ? ${defaultTarget} && targetMatrix.${defaultTarget} ? strace
        then {
          default = mkAdbPushApp {
            inherit hostPkgs targetMatrix;
            targetName = defaultTarget;
            pkgName = "strace";
            pkg = targetMatrix.${defaultTarget}.strace;
          };
        }
        else { };
    in
    builtins.listToAttrs (targetAppEntries ++ defaultAppEntries) // defaultApp;

  # Helper to create an ELF verification check derivation for CI / nix flake check
  mkElfCheck = { hostPkgs, pkg, targetName, pkgName, checkElfScript ? ../scripts/check-elf.sh }:
    hostPkgs.runCommand "check-elf-${pkgName}-${targetName}" {
      nativeBuildInputs = [
        hostPkgs.llvmPackages.llvm
        hostPkgs.file
      ];
    } ''
      bash ${checkElfScript} "${pkg}" "${targetName}" "${pkgName}" "$out"
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
    eachSystem
    mkAndroidPkgs
    mkAdbPushApp
    mkElfCheck
    mkTargetMatrix
    generatePackages
    generateApps
    generateChecks;
}
