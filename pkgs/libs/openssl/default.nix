# pkgs/libs/openssl/default.nix
# OpenSSL 3.6.3 cryptographic and SSL/TLS library ported for Android (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
}:

let
  opensslTarget =
    if stdenv.hostPlatform.isAarch64 then
      "linux-aarch64"
    else if stdenv.hostPlatform.isx86_64 then
      "linux-x86_64"
    else if stdenv.hostPlatform.isAarch32 || stdenv.hostPlatform.isArm then
      "linux-armv4"
    else if stdenv.hostPlatform.isi686 then
      "linux-x86"
    else if stdenv.hostPlatform.isRiscV64 then
      "linux64-riscv64"
    else
      throw "Unsupported OpenSSL target architecture: ${stdenv.hostPlatform.system}";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "openssl";
  version = "3.6.3";

  src = fetchurl {
    url = "https://github.com/openssl/openssl/releases/download/openssl-${finalAttrs.version}/openssl-${finalAttrs.version}.tar.gz";
    hash = "sha256-JDqGZJz28j7rai/yRW4J5dd92QGKVNPZawxr3Wumx/E=";
  };

  nativeBuildInputs = [
    buildPackages.perl
  ];

  configureScript = "./Configure";
  dontAddStaticConfigureFlags = true;
  configurePlatforms = [ ];

  configureFlags = [
    opensslTarget
    "shared"
    "--libdir=lib"
    "--openssldir=etc/ssl"
    "no-ktls"
    "no-afalgeng"
    "disable-tests"
  ];

  makeFlags = [
    "MANDIR=$(out)/share/man"
    "MANSUFFIX=ssl"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    cat << 'EOF' > "$out/bin/c_rehash"
#!/system/bin/sh
exec "$(dirname "$0")/openssl" rehash "$@"
EOF
    chmod +x "$out/bin/c_rehash"

    rm -f $out/lib/*.a
    rm -rf $out/etc/ssl/misc
  '';

  passthru = {
    dev = finalAttrs.finalPackage;
    out = finalAttrs.finalPackage;
    bin = finalAttrs.finalPackage;
  };

  meta = {
    description = "OpenSSL cryptographic and SSL/TLS toolkit for Android (Bionic)";
    homepage = "https://www.openssl.org/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    mainProgram = "openssl";
  };
})
