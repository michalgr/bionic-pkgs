# pkgs/tracing/libbpf/default.nix
# eBPF object loader and manipulation library for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  pkg-config,
  elfutils,
  android-prebuilts,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libbpf";
  version = "1.7.0";

  src = fetchurl {
    url = "https://github.com/libbpf/libbpf/archive/refs/tags/v${finalAttrs.version}.tar.gz";
    hash = "sha256-erX+/794VX9iby4+MgR4hSg5RJRxWjD8IHD83cIFG3s=";
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    elfutils
    android-prebuilts
  ];

  makeFlags = [
    "PREFIX=$(out)"
    "LIBDIR=$(out)/lib"
    "INCLUDEDIR=$(out)/include"
    "UAPIDIR=$(out)/include"
    "--directory=src"
  ];

  postPatch = ''
    substituteInPlace src/Makefile \
      --replace-warn "-Werror" ""
  '';

  postInstall = ''
    # Install libbpf-compatible UAPI headers (linux/bpf.h, linux/bpf_common.h, linux/btf.h)
    install -Dm444 include/uapi/linux/*.h -t $out/include/linux
  '';

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Library for loading eBPF programs and reading and manipulating eBPF objects from user-space";
    homepage = "https://github.com/libbpf/libbpf";
    license = with lib.licenses; [
      lgpl21Only
      bsd2
    ];
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
