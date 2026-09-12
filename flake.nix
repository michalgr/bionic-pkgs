# flake.nix
# Android 14+ (Bionic libc) cross-compilation package repository and tool suite.

{
  description = "Cross-compiled CLI tools, debugging suites, and profilers for Android 14+ (Bionic libc)";

  nixConfig = {
    extra-substituters = [ "https://bionic-pkgs.cachix.org" ];
    extra-trusted-public-keys = [
      "bionic-pkgs.cachix.org-1:6jDMfWYMBreZzvhxc33zCaASzmvW7UTKSYfWY1ThDkM="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      bionicLib = import ./lib { inherit (nixpkgs) lib; };
      bionicCompat = import ./lib/bionic-compat.nix { inherit (nixpkgs) lib; };
      packageSetFn = import ./pkgs;
    in
    {
      overlays.default =
        final: prev:
        (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.isAndroid or false) (bionicCompat final prev))
        // (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.isAndroid or false) {
          bionicPkgs = packageSetFn { targetPkgs = final; };
        });
    }
    // bionicLib.eachSystem bionicLib.supportedSystems (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Target matrix of all packages across all Android architectures
        targetMatrix = bionicLib.mkTargetMatrix {
          inherit nixpkgs system packageSetFn;
        };
      in
      {
        # Nix RFC 166 code formatter
        formatter = pkgs.nixfmt-tree;

        # Dynamically generated flat package outputs (e.g. strace, aarch64-android-strace, x86_64-android-strace)
        packages = bionicLib.generatePackages {
          inherit targetMatrix;
          inherit (bionicLib) defaultTarget;
        };

        # Hierarchical packages for nix build .#<target>.<pkg>
        legacyPackages = targetMatrix;

        # Dynamically generated ADB push deployment apps (e.g. push-strace, push-aarch64-android-strace)
        apps = bionicLib.generateApps {
          inherit targetMatrix;
          inherit (bionicLib) defaultTarget;
          hostPkgs = pkgs;
        };

        # Automated checks for CI and `nix flake check`
        checks = bionicLib.generateChecks {
          inherit targetMatrix;
          hostPkgs = pkgs;
        };

        # Development environment
        devShells.default = pkgs.mkShell {
          name = "bionic-pkgs-dev";
          packages = [
            pkgs.android-tools
            pkgs.llvmPackages.llvm
            pkgs.file
            pkgs.gh
            pkgs.nixfmt-tree
          ];

          shellHook = ''
            echo "bionic-pkgs development shell"
            echo "Host: ${system} | Default target: ${bionicLib.defaultTarget}"
            echo ""
            echo "Commands:"
            echo "  nix build .#strace                      # Build strace for ${bionicLib.defaultTarget}"
            echo "  nix build .#x86_64-android.strace       # Build strace for x86_64-android"
            echo "  nix run .#push-strace                   # Push to connected ADB device"
          '';
        };
      }
    );
}
