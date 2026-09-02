# pkgs/libs/bionic/default.nix
# Android 14+ (API 34) Bionic libc sysroot, NDK r27 headers, CRT objects, and compatibility shims.

{
  lib,
  stdenvNoCC,
  fetchzip,
}:

let
  targetArchDir =
    if stdenvNoCC.hostPlatform.isAarch64 then "aarch64-linux-android"
    else if stdenvNoCC.hostPlatform.isx86_64 then "x86_64-linux-android"
    else if stdenvNoCC.hostPlatform.isArm then "arm-linux-androideabi"
    else if stdenvNoCC.hostPlatform.isi686 then "i686-linux-android"
    else if stdenvNoCC.hostPlatform.isRiscV64 then "riscv64-linux-android"
    else throw "bionic: unsupported architecture ${stdenvNoCC.hostPlatform.parsed.cpu.name}";

  apiVersion = stdenvNoCC.hostPlatform.androidSdkVersion or "34";

  # Google Android NDK r27 platform headers (sysroot/usr/include)
  ndkHeaders = fetchzip {
    url = "https://android.googlesource.com/toolchain/prebuilts/ndk/r27/+archive/77eba0d553f8f58557f99fa98f327eb5f46e0c8c/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include.tar.gz";
    hash = "sha256-JA1JVLbea91yx7IHJ4fz4NypO7TjGt2H7kAjQbG3r3A=";
    stripRoot = false;
  };

  # Google Android NDK r27 platform shared library stubs and CRT files (sysroot/usr/lib)
  ndkLibs = fetchzip {
    url = "https://android.googlesource.com/toolchain/prebuilts/ndk/r27/+archive/77eba0d553f8f58557f99fa98f327eb5f46e0c8c/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib.tar.gz";
    hash = "sha256-fwiJ0h/wZDTzNwy8WIcw6KdLzgeLedDjZ9nR37zjk2Q=";
    stripRoot = false;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "bionic";
  version = "ndk-r27";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p "$dev/include" "$dev/lib/pkgconfig" "$dev/share/pkgconfig"
    mkdir -p "$out/lib"

    # =========================================================================
    # 1. Install NDK r27 Sysroot Headers
    # =========================================================================
    cp -rL "${ndkHeaders}"/* "$dev/include/"
    chmod -R u+w "$dev/include"

    # Promote target architecture asm headers to top-level <asm/*.h>
    if [ -d "$dev/include/${targetArchDir}/asm" ]; then
      cp -rL "$dev/include/${targetArchDir}/asm" "$dev/include/asm"
    fi

    # =========================================================================
    # 2. In-Tree Bionic Compatibility Header Fixes
    # =========================================================================

    # (a) POSIX in_addr_t and struct in_addr coordination with kernel <linux/in.h>
    # POSIX specifies in_addr_t availability in <sys/types.h>.
    # Bionic defines in_addr_t and struct in_addr in <bits/in_addr.h>.
    # We coordinate with UAPI <linux/libc-compat.h> via __UAPI_DEF_IN_ADDR so
    # kernel headers (e.g. bundled in strace) do not trigger struct in_addr redefinitions.
    cat << 'EOF' > "$dev/include/bits/in_addr.h"
#pragma once

#include <sys/cdefs.h>
#include <stdint.h>

#if !defined(_BIONIC_IN_ADDR_T_DEFINED) && !defined(__in_addr_t_defined)
#define _BIONIC_IN_ADDR_T_DEFINED 1
#define __in_addr_t_defined 1
typedef uint32_t in_addr_t;
#endif

#if !defined(_STRUCT_IN_ADDR) && (!defined(__UAPI_DEF_IN_ADDR) || __UAPI_DEF_IN_ADDR == 0)
#define _STRUCT_IN_ADDR 1
#ifndef __UAPI_DEF_IN_ADDR
#define __UAPI_DEF_IN_ADDR 0
#endif
#ifndef _NETINET_IN_H
#define _NETINET_IN_H 1
#endif
struct in_addr {
  in_addr_t s_addr;
};
#endif
EOF

    echo -e '\n#include <bits/in_addr.h>' >> "$dev/include/sys/types.h"

    # (b) GNU gettext / <libintl.h> No-op Macro Shims
    # Android Bionic libc omits GNU gettext. We provide standard no-op macro definitions
    # so software including <libintl.h> compiles cleanly without requiring external gettext.
    cat << 'EOF' > "$dev/include/libintl.h"
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

    # (c) <fnmatch.h> GNU Extension FNM_EXTMATCH
    cat << 'EOF' >> "$dev/include/fnmatch.h"

#ifndef FNM_EXTMATCH
#define FNM_EXTMATCH 0
#endif
EOF

    # (d) <elf.h> GNU Versioning and Note Types
    cat << 'EOF' >> "$dev/include/elf.h"

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

    # (e) <bits/ioctl.h> Disable C++ Signedness Overloading Ambiguity
    if [ -f "$dev/include/bits/ioctl.h" ]; then
      sed -i 's,!defined(BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD),0,g' "$dev/include/bits/ioctl.h"
    fi

    # =========================================================================
    # 3. Install Platform Shared Libraries and CRT Objects
    # =========================================================================
    apiDir=""
    if [ -d "${ndkLibs}/${targetArchDir}/${apiVersion}" ]; then
      apiDir="${ndkLibs}/${targetArchDir}/${apiVersion}"
    else
      # Fall back to highest available API level directory
      apiDir="$(ls -d "${ndkLibs}/${targetArchDir}"/[0-9]* 2>/dev/null | sort -V | tail -n 1)"
    fi

    if [ -n "$apiDir" ] && [ -d "$apiDir" ]; then
      cp -v "$apiDir"/*.so "$out/lib/" || true
      cp -v "$apiDir"/*.o "$out/lib/" || true
    fi

    # GCC CRT naming compatibility symlinks
    ln -sf crtbegin_dynamic.o "$out/lib/crtbegin.o"
    ln -sf crtbegin_so.o "$out/lib/crtbeginS.o"
    ln -sf crtbegin_static.o "$out/lib/crtbeginT.o"
    ln -sf crtend_android.o "$out/lib/crtend.o"
    ln -sf crtend_so.o "$out/lib/crtendS.o"

    # Install compiler-rt extras if present
    if [ -f "${ndkLibs}/${targetArchDir}/libcompiler_rt-extras.a" ]; then
      cp -v "${ndkLibs}/${targetArchDir}/libcompiler_rt-extras.a" "$out/lib/"
    fi

    # Remove any C++ runtime stubs from Bionic sysroot so they don't shadow or conflict with source-built libcxx
    rm -f "$out/lib"/libc++*.so "$out/lib"/libc++*.a

    # =========================================================================
    # 4. GNU Linker Script Shims for Unified Bionic libc
    # =========================================================================
    # Bionic consolidates pthread, rt, dl, util, etc. into libc.so.
    # GNU linker scripts redirect legacy glibc library links directly to Bionic libc.so
    for libname in libpthread.so libpthread.a librt.so librt.a libutil.so libutil.a libresolv.so libresolv.a libcrypt.so libcrypt.a libnsl.so libnsl.a libanl.so libanl.a libatomic.so libatomic.a; do
      echo "INPUT(libc.so)" > "$out/lib/$libname"
    done
    echo "INPUT(libdl.so)" > "$out/lib/libdl.a"
    echo "INPUT(libm.so)" > "$out/lib/libm.a"
    echo "INPUT(libc.so)" > "$out/lib/libc.a"
    echo "INPUT(libc.so)" > "$out/lib/libgcc.a"
    echo "INPUT(libc.so)" > "$out/lib/libgcc_s.so"
    echo "INPUT(-lz)" > "$out/lib/libz.a"
    echo "INPUT(-llog)" > "$out/lib/liblog.a"

    # =========================================================================
    # 5. Pkg-config Definitions for Android Platform zlib
    # =========================================================================
    cat << EOF > "$dev/lib/pkgconfig/zlib.pc"
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${prefix}/lib
sharedlibdir=\''${prefix}/lib
includedir=$dev/include

Name: zlib
Description: Android platform zlib compression library
Version: 1.3.2
Requires:
Libs: -L\''${libdir} -lz
Cflags: -I\''${includedir}
EOF
    cp "$dev/lib/pkgconfig/zlib.pc" "$dev/share/pkgconfig/zlib.pc"
  '';

  outputs = [
    "out"
    "dev"
  ];

  passthru = {
    linuxHeaders = finalAttrs.finalPackage.dev;
  };

  meta = {
    description = "Android Bionic libc implementation and NDK r27 sysroot with built-in compatibility shims";
    homepage = "https://android.googlesource.com/platform/bionic/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    skipElfCheck = true;
  };
})
