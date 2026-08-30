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
    for libname in libpthread.so libpthread.a librt.so librt.a libutil.so libutil.a libresolv.so libresolv.a libcrypt.so libcrypt.a libnsl.so libnsl.a libanl.so libanl.a libatomic.so libatomic.a; do
      echo "INPUT(libc.so)" > "$out/lib/$libname"
    done
    echo "INPUT(libdl.so)" > "$out/lib/libdl.a"
    echo "INPUT(libm.so)" > "$out/lib/libm.a"
    echo "INPUT(libc.so)" > "$out/lib/libc.a"

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

    # 6. Header Shim: <libintl.h>
    # Android Bionic libc omits GNU gettext / libintl. We provide standard no-op macro definitions
    # so packages that include <libintl.h> compile cleanly without requiring external gettext.
    cat << 'EOF' > "$out/include/libintl.h"
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#define gettext(Msgid) ((char *)(Msgid))
#define dgettext(Domainname, Msgid) ((char *)(Msgid))
#define dcgettext(Domainname, Msgid, Category) ((char *)(Msgid))
#define ngettext(Singular, Plural, N) ((char *)((N) == 1 ? (Singular) : (Plural)))
#define dngettext(Domainname, Singular, Plural, N) ((char *)((N) == 1 ? (Singular) : (Plural)))
#define dcngettext(Domainname, Singular, Plural, N, Category) ((char *)((N) == 1 ? (Singular) : (Plural)))
#define textdomain(Domainname) ((char *)(Domainname))
#define bindtextdomain(Domainname, Dirname) ((char *)(Dirname))
#define bind_textdomain_codeset(Domainname, Codeset) ((char *)(Codeset))

#ifdef __cplusplus
}
#endif
EOF

    # 7. Header Shim: <fnmatch.h>
    # Bionic defines POSIX fnmatch() constants but omits the GNU extension FNM_EXTMATCH.
    cat << 'EOF' > "$out/include/fnmatch.h"
#pragma once
#include_next <fnmatch.h>
#ifndef FNM_EXTMATCH
#define FNM_EXTMATCH 0
#endif
EOF

    # 8. Header Shim: <elf.h>
    # Bionic defines standard ELF constants but omits GNU versioning section types and GNU note types.
    cat << 'EOF' > "$out/include/elf.h"
#pragma once
#include_next <elf.h>
#ifndef SHT_GNU_INCREMENTAL_INPUTS
#define SHT_GNU_INCREMENTAL_INPUTS 0x6fff4700
#endif
#ifndef SHT_GNU_ATTRIBUTES
#define SHT_GNU_ATTRIBUTES 0x6ffffff5
#endif
#ifndef SHT_GNU_HASH
#define SHT_GNU_HASH 0x6ffffff6
#endif
#ifndef SHT_GNU_LIBLIST
#define SHT_GNU_LIBLIST 0x6ffffff7
#endif
#ifndef SHT_GNU_verdef
#define SHT_GNU_verdef 0x6ffffffd
#endif
#ifndef SHT_GNU_verneed
#define SHT_GNU_verneed 0x6ffffffe
#endif
#ifndef SHT_GNU_versym
#define SHT_GNU_versym 0x6fffffff
#endif
#ifndef NT_GNU_ABI_TAG
#define NT_GNU_ABI_TAG 1
#endif
#ifndef NT_GNU_HWCAP
#define NT_GNU_HWCAP 2
#endif
#ifndef NT_GNU_BUILD_ID
#define NT_GNU_BUILD_ID 3
#endif
#ifndef NT_GNU_GOLD_VERSION
#define NT_GNU_GOLD_VERSION 4
#endif
#ifndef NT_GNU_PROPERTY_TYPE_0
#define NT_GNU_PROPERTY_TYPE_0 5
#endif
EOF

    # 9. Header Shim: <linux/capability.h>
    # Modern Linux capabilities (CAP_PERFMON=38, CAP_BPF=39, CAP_CHECKPOINT_RESTORE=40)
    mkdir -p "$out/include/linux"
    cat << 'EOF' > "$out/include/linux/capability.h"
#pragma once
#include_next <linux/capability.h>
#ifndef CAP_PERFMON
#define CAP_PERFMON 38
#endif
#ifndef CAP_BPF
#define CAP_BPF 39
#endif
#ifndef CAP_CHECKPOINT_RESTORE
#define CAP_CHECKPOINT_RESTORE 40
#endif
EOF
  '';

  meta = {
    description = "Compatibility header shims and linker scripts for Android Bionic targets";
    homepage = "https://github.com/michalgr/bionic-pkgs";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    skipElfCheck = true;
  };
}
