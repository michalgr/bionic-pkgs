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

  # Re-export Bionic compatibility overlay helper
  bionicCompat = import ./bionic-compat.nix { inherit lib; };

  # Native helper to map outputs over supported host systems
  eachSystem = systemsOrFn:
    let
      f = if builtins.isFunction systemsOrFn then systemsOrFn else null;
      impl = systems: fn:
        let
          perSystem = lib.genAttrs systems fn;
        in
        {
          packages = lib.mapAttrs (_: s: s.packages or { }) perSystem;
          legacyPackages = lib.mapAttrs (_: s: s.legacyPackages or { }) perSystem;
          apps = lib.mapAttrs (_: s: s.apps or { }) perSystem;
          checks = lib.mapAttrs (_: s: s.checks or { }) perSystem;
          devShells = lib.mapAttrs (_: s: s.devShells or { }) perSystem;
        };
    in
    if f != null then impl supportedSystems f else impl systemsOrFn;

  # Helper to instantiate nixpkgs with Bionic cross-compilation overlays
  mkAndroidPkgs = { nixpkgs, system, targetName }:
    let
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
      binName = pkg.meta.mainProgram or pkgName;
      directDeps = lib.filter (d: lib.isDerivation d && d ? outPath) (
        (pkg.buildInputs or [ ]) ++ (pkg.propagatedBuildInputs or [ ])
      );
      allDeps = lib.closePropagation directDeps;
      pushScript = hostPkgs.writeShellScript "push-${pkgName}-${targetName}" ''
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
      program = "${pushScript}";
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
  isRunnableApp = pkg: lib.isDerivation pkg && (pkg.meta ? mainProgram);

  # Helper to determine if a package can be verified for ELF properties (excluding header/shim/prebuilt-only packages)
  isCheckablePkg = pkg: lib.isDerivation pkg && (pkg ? pname) && !(pkg.meta.skipElfCheck or false);

  # Shared helper to iterate over targetMatrix and build attribute sets of outputs
  mapMatrix = { targetMatrix, defaultTarget ? null, filter ? (_: true), mkEntry }:
    let
      targetEntries = lib.concatMap (targetName:
        let pkgsForTarget = targetMatrix.${targetName};
        in lib.concatMap (pkgName:
          let pkg = pkgsForTarget.${pkgName};
          in lib.optional (filter pkg) (mkEntry {
            inherit targetName pkgName pkg;
            isDefault = false;
          })
        ) (builtins.attrNames pkgsForTarget)
      ) (builtins.attrNames targetMatrix);

      defaultEntries = if defaultTarget != null && targetMatrix ? ${defaultTarget} then
        let pkgsForTarget = targetMatrix.${defaultTarget};
        in lib.concatMap (pkgName:
          let pkg = pkgsForTarget.${pkgName};
          in lib.optional (filter pkg) (mkEntry {
            targetName = defaultTarget;
            inherit pkgName pkg;
            isDefault = true;
          })
        ) (builtins.attrNames pkgsForTarget)
      else [ ];
    in
    builtins.listToAttrs (targetEntries ++ defaultEntries);

  # Automatically generates flat package outputs from targetMatrix
  generatePackages = { targetMatrix, defaultTarget ? "aarch64-android", defaultPkg ? "strace" }:
    let
      entries = mapMatrix {
        inherit targetMatrix defaultTarget;
        filter = lib.isDerivation;
        mkEntry = { targetName, pkgName, pkg, isDefault }: {
          name = if isDefault then pkgName else "${targetName}-${pkgName}";
          value = pkg;
        };
      };
      defaultPackage = if defaultTarget != null && defaultPkg != null && targetMatrix ? ${defaultTarget} && targetMatrix.${defaultTarget} ? ${defaultPkg}
        then { default = targetMatrix.${defaultTarget}.${defaultPkg}; }
        else { };
    in
    entries // defaultPackage;

  # Automatically generates ADB push apps from targetMatrix
  generateApps = { hostPkgs, targetMatrix, defaultTarget ? "aarch64-android", defaultPkg ? "strace" }:
    let
      entries = mapMatrix {
        inherit targetMatrix defaultTarget;
        filter = isRunnableApp;
        mkEntry = { targetName, pkgName, pkg, isDefault }: {
          name = if isDefault then "push-${pkgName}" else "push-${targetName}-${pkgName}";
          value = mkAdbPushApp {
            inherit hostPkgs targetName pkgName pkg;
          };
        };
      };
      defaultApp = if defaultTarget != null && defaultPkg != null && targetMatrix ? ${defaultTarget} && targetMatrix.${defaultTarget} ? ${defaultPkg}
        then {
          default = mkAdbPushApp {
            inherit hostPkgs;
            targetName = defaultTarget;
            pkgName = defaultPkg;
            pkg = targetMatrix.${defaultTarget}.${defaultPkg};
          };
        }
        else { };
    in
    entries // defaultApp;

  # Helper to create an ELF verification check derivation for CI / nix flake check
  mkElfCheck = { hostPkgs, pkg, targetName, pkgName, checkElfScript ? ../scripts/check-elf.sh }:
    hostPkgs.runCommand "check-elf-${pkgName}-${targetName}" {
      nativeBuildInputs = [
        hostPkgs.llvmPackages.llvm
        hostPkgs.file
      ];
    } ''
      bash ${checkElfScript} "${pkg}" "${targetName}" "${pkgName}"
    '';

  # Automatically generates checks for all target matrix packages
  generateChecks = { hostPkgs, targetMatrix }:
    mapMatrix {
      inherit targetMatrix;
      filter = isCheckablePkg;
      mkEntry = { targetName, pkgName, pkg, ... }: {
        name = "check-elf-${targetName}-${pkgName}";
        value = mkElfCheck {
          inherit hostPkgs targetName pkgName pkg;
        };
      };
    };

in
{
  inherit
    targetPlatforms
    supportedTargets
    defaultTarget
    supportedSystems
    bionicCompat
    eachSystem
    mkAndroidPkgs
    mkAdbPushApp
    mkElfCheck
    mkTargetMatrix
    mapMatrix
    generatePackages
    generateApps
    generateChecks;
}
