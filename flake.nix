# flake.nix
# Android 14+ (Bionic libc) cross-compilation package repository and tool suite.

{
  description = "Cross-compiled CLI tools, debugging suites, and profilers for Android 14+ (Bionic libc)";

  nixConfig = {
    extra-substituters = [ "https://bionic-pkgs.cachix.org" ];
    extra-trusted-public-keys = [ "bionic-pkgs.cachix.org-1:6jDMfWYMBreZzvhxc33zCaASzmvW7UTKSYfWY1ThDkM=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      bionicLib = import ./lib { inherit (nixpkgs) lib; };
      bionicCompat = import ./lib/bionic-compat.nix { inherit (nixpkgs) lib; };
      packageSetFn = import ./pkgs;
    in
    {
      overlays.default = final: prev:
        (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.isAndroid or false) (bionicCompat final prev))
        // (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.isAndroid or false) {
          bionicPkgs = packageSetFn { targetPkgs = final; };
        });
    }
    // bionicLib.mkFlakeOutputs {
      inherit nixpkgs packageSetFn;
    };
}
