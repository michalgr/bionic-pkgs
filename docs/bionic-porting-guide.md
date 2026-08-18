# Bionic Cross-Compilation & Porting Guide

Cross-compiling C/C++ applications for Android's **Bionic libc** differs significantly from standard GLIBC or Musl Linux environments. This guide documents Bionic quirks, patch patterns, target ABIs, and Nix-specific cross-compilation techniques used in `bionic-pkgs`.

---

## 1. Key Differences & Binary Requirements

1. **Combined `libc.so` (No `libpthread`, `librt`, `libutil`, `libresolv`, `libcrypt`)**:
   - In Bionic, POSIX threads (`pthread_*`), real-time timers (`clock_gettime`), dynamic loading (`dlopen`), and standard utilities are compiled directly into `libc.so`. (`libdl.so` and `libm.so` exist as stub libraries on device).
   - **Fix**: Strip `-lpthread -lrt -lutil -lresolv -lcrypt -lnsl` from `LDFLAGS` and build configurations, or provide GNU linker script stubs (`INPUT(-lc)`) inside `bionic.out/lib`.

2. **Missing or Non-Standard POSIX APIs**:
   - **No Thread Cancellation**: `pthread_cancel()`, `pthread_testcancel()`, and `pthread_setcancelstate()` do **not** exist in Bionic. Multithreaded software must use atomic flags or signal handling for cooperative termination.
   - **No System V IPC**: `<sys/shm.h>`, `<sys/ipc.h>`, `<sys/sem.h>`, and `<sys/msg.h>` are completely absent. Software must use POSIX shared memory (`shm_open`), `memfd_create()`, or anonymous `mmap()`.
   - **No `/etc/passwd` or `/etc/group` Databases**: `fgetpwent()`, `getpwent()`, and `getgrent()` are absent. Android UIDs/GIDs are managed by system services and `<android_filesystem_config.h>`.
   - **No `<wordexp.h>`**: Word expansion is not supported.
   - **No Native `<iconv.h>`**: Character encoding conversions require linking against an external `libiconv` derivation.
   - **No `<execinfo.h>` (`backtrace()`)**: Call stack inspection must use `<unwind.h>` or Android's `libunwindstack`.
   - **Signal Reservations**: Real-time signals `SIGRTMIN` through `__SIGRTMIN + 7` are reserved internally by Bionic's pthread implementation.

3. **Position Independent Executables (PIE)**:
   - Android 5.0+ (API 21+) strictly enforces PIE. Non-PIE executables are rejected at runtime by `/system/bin/linker` / `/system/bin/linker64` with `error: only position independent executables (PIE) are supported`.
   - Must be compiled with `-fPIE` and linked with `-pie`.

4. **16 KB Memory Page Alignment (`-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384`)**:
   - Android 15+ (API 35+) mandates **16 KB ELF memory page alignment** for all native binaries and shared libraries on ARM64.
   - Linkers must be passed `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384` so that `PT_LOAD` segments align to `0x4000` boundaries, enabling smooth loading across both 4 KB and 16 KB kernels.

5. **C++ Standard Library (STL) Architecture (LLVM `libc++` from Source vs NDK Prebuilts)**:
   - `bionic-pkgs` compiles LLVM's `libc++` and `libc++abi` directly from source against Bionic libc, rather than using Google's prebuilt NDK `libc++_shared.so` / `libc++_static.a`.
   - **Rationale**:
     - Eliminates opaque prebuilt binary blobs from the build chain.
     - Unlocks complete C++20, C++23, and C++26 standard library features matching the compiler.
     - Enforces 16 KB page alignment and consistent security hardening modes (`_LIBCPP_HARDENING_MODE`).
     - Integrates with `llvm-libunwind` built directly from source.

---

## 2. API Levels & Target ABIs

Android NDK and Bionic APIs are tied to the **Android API Level** (e.g., API 34 = Android 14).

In `bionic-pkgs`:
- **Default API Level**: `34` (Android 14+).
- **Supported Target ABIs**:
  - `aarch64-android` (`arm64-v8a` / `aarch64-linux-android` — Primary)
  - `x86_64-android` (`x86_64` / `x86_64-linux-android`)
  - `armv7a-android` (`armeabi-v7a` / `armv7a-linux-androideabi`)
  - `i686-android` (`x86` / `i686-linux-android`)

---

## 3. Standard Patch Patterns in Nix

### Standalone Compatibility Package (`pkgs/libs/bionic-compat`)
Rather than mutating upstream Bionic sysroot derivations in-place, `bionic-pkgs` employs a dedicated `bionic-compat` package providing:
1. **GNU Linker Script Shims**: Provides `INPUT(-lc)` stubs for `libpthread.so`, `libpthread.a`, `librt.so`, `librt.a`, `libutil.so`, `libutil.a`, `libresolv.so`, `libresolv.a`, `libcrypt.so`, `libcrypt.a`.
2. **Header Shims via `#include_next`**: Wraps Bionic headers cleanly without in-place mutation:
   - `<netinet/in.h>`: Injects `typedef uint32_t in_addr_t;`.
   - `<arpa/inet.h>`: Guarantees `<netinet/in.h>` is parsed before Bionic's `<arpa/inet.h>`.
   - `<asm/stat.h>`: Uses `#pragma push_macro("__unused")` / `#undef __unused` to prevent macro collisions with Bionic `<sys/cdefs.h>`.

Injected automatically into the cross-compiler wrapper via `-isystem ${bionic-compat}/include` and `-L${bionic-compat}/lib`.

### Stripping Unneeded System Libraries (`-lpthread`, `-lrt`, `-lutil`)
When Autotools or CMake scripts try to link `-lpthread` or `-lrt`:
```nix
# In derivation overlay:
postPatch = ''
  substituteInPlace configure \
    --replace-warn "-lpthread" "" \
    --replace-warn "-lrt" "" \
    --replace-warn "-lutil" ""
'';
```

### Enforcing PIE (`-fPIE -pie`) and 16 KB Page Alignment (`-z max-page-size=16384`)
Nixpkgs cross-stdenv or `bionic-compat` hooks inject these flags into derivation environments:
```nix
# In derivation:
hardeningEnable = [ "pie" ];
NIX_CFLAGS_COMPILE = "-fPIE";
NIX_LDFLAGS = "-pie -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384";
```

### Dynamic Linker Path (`/system/bin/linker64` / `/system/bin/linker`) & `$ORIGIN` RPATH
Android binaries locate their dynamic linker at:
- `/system/bin/linker64` (64-bit targets: `aarch64-android`, `x86_64-android`)
- `/system/bin/linker` (32-bit targets: `armv7a-android`, `i686-android`)

In `lib/bionic-compat.nix`, `bionicFixupHook` automatically ensures target ELF binaries have relative runpaths for device portability:
```nix
bionicFixup() {
  for output in "''${outputs[@]:-out}"; do
    local dir="''${!output:-}"
    if [ -n "$dir" ] && [ -d "$dir" ]; then
      find "$dir" -type f \( -perm -0100 -o -name "*.so*" \) -print0 | while IFS= read -r -d "" elf; do
        if [ -f "$elf" ] && [ "$(head -c 4 "$elf" 2>/dev/null)" = $'\x7fELF' ]; then
          chmod +w "$elf" 2>/dev/null || true
          patchelf --set-rpath '$ORIGIN/../lib:$ORIGIN/lib' "$elf" 2>/dev/null || true
        fi
      done
    fi
  done
}
```

---

## 4. Dynamic Page Size Handling

Modern Android kernels (Android 15+) support both 4 KB and 16 KB page sizes. On 64-bit architectures, Bionic headers intentionally omit or deprecate the compile-time `PAGE_SIZE` macro to prevent developers from hardcoding `4096`.

### 1. Dynamic Runtime Lookup
Always query the page size dynamically at runtime:
```c
#include <unistd.h>

/* Correct dynamic page size lookup */
long page_size = sysconf(_SC_PAGESIZE);
/* Alternatively: long page_size = getpagesize(); */
```

### 2. Common Code Porting Patterns:
- **Static Buffer Declarations**:
  ```c
  // WRONG: Breaks when PAGE_SIZE is not defined or page size is 16 KB
  char buffer[PAGE_SIZE];

  // CORRECT: Dynamically allocate or use explicit fixed buffer size
  char *buffer = malloc(sysconf(_SC_PAGESIZE));
  // Or: char buffer[65536];
  ```
- **Page Alignment Bitmasks**:
  ```c
  // WRONG:
  uintptr_t aligned_addr = addr & ~(PAGE_SIZE - 1);

  // CORRECT:
  long ps = sysconf(_SC_PAGESIZE);
  uintptr_t aligned_addr = addr & ~(ps - 1);
  ```

---

## 5. Case Studies & Package Solutions

### Case Study 1: `strace`
`strace` is our baseline canary package demonstrating userspace system call tracing on Android.

1. **Unwind Implementation (`nongnu-libunwind` vs LLVM / Android)**:
   - `pkgs.libunwind` (nongnu-libunwind) fails to compile against Bionic because its coredump/procfs handlers require glibc's `struct elf_prstatus` which is absent from Android's `<sys/procfs.h>`.
   - **Resolution**: Disable `nongnu-libunwind` and `elfutils` debuginfod in `pkgs/diagnostics/strace/default.nix`.
2. **Native Build Machine Code Generator (`CC_FOR_BUILD`)**:
   - `strace` compiles native build-time generator tools (`ioctlsort0`, `ioctlsort1`) during cross-compilation.
   - **Resolution**: Add `depsBuildBuild = [ buildPackages.stdenv.cc ];` so the build machine compiler and linker are cleanly available during the build phase.
3. **Missing `in_addr_t` in Bionic `<netinet/in.h>`**:
   - Bionic NDK headers define `in_port_t` in `<netinet/in.h>` but omit `typedef uint32_t in_addr_t;` (which is in kernel `<linux/in.h>`).
   - **Resolution**: Layer `<netinet/in.h>`, `<arpa/inet.h>`, and `<sys/types.h>` shims in `pkgs/libs/bionic-compat` using `#include_next` to define `in_addr_t` transparently.
4. **Macro Collisions with `__unused` in `<sys/cdefs.h>`**:
   - Bionic defines `#define __unused __attribute__((__unused__))` in `<sys/cdefs.h>`. When Linux UAPI headers like `<asm/stat.h>` declare fields named `__unused`, compilation fails with syntax errors.
   - **Resolution**: Wrap `<asm/stat.h>` in `pkgs/libs/bionic-compat` with `#pragma push_macro("__unused")` / `#undef __unused` / `#include_next <asm/stat.h>` / `#pragma pop_macro("__unused")`.

---

## 6. Testing & Verifying Cross-Compiled Binaries

1. **Verify ELF Header, Linker & 16 KB Page Alignment**:
   ```bash
   # Inspect architecture and interpreter:
   file result/bin/strace

   # Verify LOAD segment alignment (all LOAD segments must have Align >= 0x4000):
   llvm-readelf -l result/bin/strace | grep -E 'LOAD|Align'
   ```

2. **Verify Shared Library Dependencies & Runpaths**:
   ```bash
   # Verify dynamic tags (libc.so, libm.so, and relative runpaths):
   llvm-readelf -d result/bin/strace | grep -E 'NEEDED|RPATH|RUNPATH'
   ```

3. **Execute via ADB on Android Device / Emulator**:
   ```bash
   # Use the automated flake push app:
   nix run .#push-strace

   # Or manual transfer:
   adb push result/bin/strace /data/local/tmp/
   adb shell chmod 755 /data/local/tmp/strace
   adb shell /data/local/tmp/strace -V
   ```
