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

  # Evaluates packages for target architectures
  mkTargetMatrix = { nixpkgs, system, packageSetFn, targets ? supportedTargets }:
    builtins.listToAttrs (map (targetName: {
      name = targetName;
      value = packageSetFn {
        targetPkgs = mkAndroidPkgs { inherit nixpkgs system targetName; };
      };
    }) targets);

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
  generateApps = { hostPkgs ? null, nixpkgs ? null, system ? null, targetMatrix, defaultTarget ? "aarch64-android" }:
    let
      effectiveHostPkgs = if hostPkgs != null then hostPkgs else import nixpkgs { inherit system; };

      targetAppEntries = lib.concatMap (targetName:
        let pkgsForTarget = targetMatrix.${targetName};
        in lib.concatMap (pkgName:
          let pkg = pkgsForTarget.${pkgName};
          in lib.optional (isRunnableApp pkg) {
            name = "push-${targetName}-${pkgName}";
            value = mkAdbPushApp {
              hostPkgs = effectiveHostPkgs;
              inherit targetName pkgName pkg;
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
              hostPkgs = effectiveHostPkgs;
              inherit pkgName pkg;
              targetName = defaultTarget;
            };
          }
        ) (builtins.attrNames targetMatrix.${defaultTarget})
      else [ ];

      defaultApp = if targetMatrix ? ${defaultTarget} && targetMatrix.${defaultTarget} ? strace
        then {
          default = mkAdbPushApp {
            hostPkgs = effectiveHostPkgs;
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
  generateChecks = { hostPkgs ? null, nixpkgs ? null, system ? null, targetMatrix }:
    let
      effectiveHostPkgs = if hostPkgs != null then hostPkgs else import nixpkgs { inherit system; };

      checkEntries = lib.concatMap (targetName:
        let pkgsForTarget = targetMatrix.${targetName};
        in lib.concatMap (pkgName:
          let pkg = pkgsForTarget.${pkgName};
          in lib.optional (isCheckablePkg pkg) {
            name = "check-elf-${targetName}-${pkgName}";
            value = mkElfCheck {
              hostPkgs = effectiveHostPkgs;
              inherit targetName pkgName pkg;
            };
          }
        ) (builtins.attrNames pkgsForTarget)
      ) (builtins.attrNames targetMatrix);
    in
    builtins.listToAttrs checkEntries;

  # Creates default devShell for target matrix environment
  mkDevShell = { hostPkgs ? null, nixpkgs ? null, system ? null, targetMatrix ? null, defaultTarget ? "aarch64-android" }:
    let
      pkgs = if hostPkgs != null then hostPkgs else import nixpkgs { inherit system; };
      sysName = if system != null then system else pkgs.stdenv.hostPlatform.system;
    in
    pkgs.mkShell {
      name = "bionic-pkgs-dev";
      packages = [
        pkgs.android-tools
        pkgs.llvmPackages.llvm
        pkgs.file
      ];

      shellHook = ''
        echo "bionic-pkgs development shell"
        echo "Host: ${sysName} | Default target: ${defaultTarget}"
        echo ""
        echo "Commands:"
        echo "  nix build .#strace                      # Build strace for ${defaultTarget}"
        echo "  nix build .#x86_64-android.strace       # Build strace for x86_64-android"
        echo "  nix run .#push-strace                   # Push to connected ADB device"
      '';
    };

  # Encapsulates flake output matrix generation
  mkFlakeOutputs = { nixpkgs, packageSetFn, systems ? supportedSystems, targets ? supportedTargets, defaultTarget ? "aarch64-android" }:
    eachSystem systems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        targetMatrix = mkTargetMatrix { inherit nixpkgs system packageSetFn targets; };
      in
      {
        packages = generatePackages { inherit targetMatrix defaultTarget; };
        legacyPackages = targetMatrix;
        apps = generateApps { inherit nixpkgs system targetMatrix defaultTarget; };
        checks = generateChecks { inherit nixpkgs system targetMatrix; };
        devShells.default = mkDevShell { inherit nixpkgs system targetMatrix defaultTarget; };
      }
    );

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
    generateChecks
    mkDevShell
    mkFlakeOutputs;
}
