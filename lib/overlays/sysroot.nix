# lib/overlays/sysroot.nix
# Bionic libc sysroot, platform library stubs, and sanitized kernel headers overlay.

{ lib }:

final: prev: {
  # Custom Android 14+ (API 34) Bionic libc & NDK r27 sysroot with built-in shims
  bionic = final.callPackage ../sysroot { };

  # Map zlib to Android platform NDK stubs so all packages bind directly to /system/lib64/libz.so
  zlib = final.bionic // {
    dev = final.bionic;
    out = final.bionic;
    static = final.bionic;
  };

  # Expose Linux kernel headers from sanitized Bionic sysroot
  linuxHeaders = final.bionic.dev;
}
