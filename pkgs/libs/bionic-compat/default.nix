# pkgs/libs/bionic-compat/default.nix
# Compatibility shims and GNU linker scripts for Android Bionic targets.

{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "bionic-compat";
  version = "1.0.0";

  dontUnpack = true;

  installPhase = ''
    mkdir -p "$out/lib" "$out/include/netinet" "$out/include/arpa" "$out/include/sys" "$out/include/asm"

    # 1. GNU Linker Script Shims
    # On Android Bionic, POSIX threads, real-time timers, dlopen, and utilities
    # are consolidated directly into libc.so. We provide GNU linker script stubs
    # that redirect legacy glibc split library link flags (-lpthread, -lrt, etc.)
    # to Bionic libc without polluting DT_NEEDED.
    for libname in libpthread.so libpthread.a librt.so librt.a libutil.so libutil.a libresolv.so libresolv.a libcrypt.so libcrypt.a libnsl.so libnsl.a libanl.so libanl.a; do
      echo "INPUT(-lc)" > "$out/lib/$libname"
    done

    # 2. Header Shim: <netinet/in.h>
    # Bionic NDK headers define in_port_t in <netinet/in.h> but omit typedef uint32_t in_addr_t
    # (which is defined in kernel <linux/in.h>). This shim layers over Bionic's header via #include_next.
    cat << 'EOF' > "$out/include/netinet/in.h"
#pragma once
#include_next <netinet/in.h>
#if !defined(_BIONIC_COMPAT_IN_ADDR_T_DEFINED) && !defined(__in_addr_t_defined)
#define _BIONIC_COMPAT_IN_ADDR_T_DEFINED 1
#define __in_addr_t_defined 1
#include <stdint.h>
typedef uint32_t in_addr_t;
#endif
EOF

    # 3. Header Shim: <arpa/inet.h>
    # Ensure <netinet/in.h> and in_addr_t are loaded prior to Bionic's <arpa/inet.h>.
    cat << 'EOF' > "$out/include/arpa/inet.h"
#pragma once
#include <netinet/in.h>
#include_next <arpa/inet.h>
EOF

    # 4. Header Shim: <sys/types.h>
    # POSIX specifies in_addr_t availability in <sys/types.h>.
    cat << 'EOF' > "$out/include/sys/types.h"
#pragma once
#include_next <sys/types.h>
#if !defined(_BIONIC_COMPAT_IN_ADDR_T_DEFINED) && !defined(__in_addr_t_defined)
#define _BIONIC_COMPAT_IN_ADDR_T_DEFINED 1
#define __in_addr_t_defined 1
#include <stdint.h>
typedef uint32_t in_addr_t;
#endif
EOF

    # 5. Header Shim: <asm/stat.h>
    # Bionic defines `#define __unused __attribute__((__unused__))` in <sys/cdefs.h>,
    # which conflicts with struct fields named `__unused` in kernel stat headers on x86_64.
    # We temporarily undefine __unused around the kernel header inclusion.
    cat << 'EOF' > "$out/include/asm/stat.h"
#pragma once
#pragma push_macro("__unused")
#undef __unused
#include_next <asm/stat.h>
#pragma pop_macro("__unused")
EOF
  '';

  meta = {
    description = "Compatibility header shims and linker scripts for Android Bionic targets";
    homepage = "https://github.com/michalgr/bionic-pkgs";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
