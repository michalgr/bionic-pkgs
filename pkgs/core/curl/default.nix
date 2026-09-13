# pkgs/core/curl/default.nix
# cURL command-line tool and libcurl library for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  cmake,
  ninja,
  pkg-config,
  openssl,
  zlib,
  zstd,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "curl";
  version = "8.22.0";

  src = fetchurl {
    urls = [
      "https://curl.se/download/curl-${finalAttrs.version}.tar.xz"
      "https://github.com/curl/curl/releases/download/curl-${
        builtins.replaceStrings [ "." ] [ "_" ] finalAttrs.version
      }/curl-${finalAttrs.version}.tar.xz"
    ];
    hash = "sha256-9+866KIuUh8omAP+k1Q+tkwym1iqc6niJN/ZFaKl9Pc=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    openssl
    zlib
    zstd
  ];

  # Bionic Porting Notes:
  # 1. Native CMake Cross-Compilation:
  #    Using CMake avoids Autotools AC_RUN_IFELSE / cross-compilation errors, cleanly generating libcurl.pc and curl binary.
  # 2. OpenSSL 3 TLS Support:
  #    Enables HTTPS and secure transfers without glibc dependencies.
  # 3. Android CA Certificate Path:
  #    Android stores system CA certificates in /system/etc/security/cacerts/ as hashed PEM files (*.0).
  #    Setting CURL_CA_PATH and enabling CURL_CA_FALLBACK allows curl to verify TLS out-of-the-box on Android.
  # 4. Compression Libraries:
  #    Links against Android platform libz.so and cross-compiled libzstd.so.
  # 5. Feature Pruning for Embedded Footprint:
  #    Disables unnecessary server/desktop protocols (LDAP, manual docs, libssh2, libpsl, libidn2, nghttp2).
  cmakeFlags = [
    "-DBUILD_CURL_EXE=ON"
    "-DBUILD_SHARED_LIBS=ON"
    "-DBUILD_STATIC_LIBS=OFF"
    "-DBUILD_TESTING=OFF"
    "-DENABLE_CURL_MANUAL=OFF"
    "-DBUILD_LIBCURL_DOCS=OFF"
    "-DBUILD_MISC_DOCS=OFF"
    "-DCURL_ENABLE_SSL=ON"
    "-DCURL_USE_OPENSSL=ON"
    "-DCURL_ZLIB=ON"
    "-DCURL_ZSTD=ON"
    "-DCURL_DISABLE_LDAP=ON"
    "-DCURL_DISABLE_LDAPS=ON"
    "-DUSE_NGHTTP2=OFF"
    "-DCURL_USE_LIBSSH2=OFF"
    "-DCURL_USE_LIBPSL=OFF"
    "-DUSE_LIBIDN2=OFF"
    "-DCURL_CA_PATH=/system/etc/security/cacerts"
    "-DCURL_CA_FALLBACK=ON"
  ];

  enableParallelBuilding = true;
  doCheck = false;

  meta = {
    description = "Command line tool and library for transferring data with URLs on Android (Bionic)";
    homepage = "https://curl.se/";
    license = lib.licenses.curl;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "curl";
  };
})
