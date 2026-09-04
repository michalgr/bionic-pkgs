# Bionic Cross-Compilation & Porting Guide

Cross-compiling C/C++ applications for Android's **Bionic libc** differs significantly from standard GLIBC or Musl Linux environments. This guide documents Bionic quirks, patch patterns, target ABIs, and Nix-specific cross-compilation techniques used in `bionic-pkgs`.

---

## 1. Key Differences & Binary Requirements

1. **Combined `libc.so` (No `libpthread`, `librt`, `libutil`, `libresolv`, `libcrypt`)**:
   - In Bionic, POSIX threads (`pthread_*`), real-time timers (`clock_gettime`), dynamic loading (`dlopen`), and standard utilities are compiled directly into `libc.so`. (`libdl.so` and `libm.so` exist as stub libraries on device).
   - **Fix**: Strip `-lpthread -lrt -lutil -lresolv -lcrypt -lnsl` from `LDFLAGS` and build configurations, or provide GNU linker script stubs (`INPUT(-lc)`) inside `bionic.out/lib`.

2. **Missing or Non-Standard POSIX APIs**:
   - **No Thread Cancellation**: `pthread_cancel()`, `pthread_testcancel()`, and `pthread_setcancelstate()` do **not** exist in Bionic. Multithreaded software must use atomic flags or signal handling for cooperative termination.
   - **No System V IPC**: `<sys/ipc.h>`, `<sys/sem.h>`, and `<sys/msg.h>` are absent in Bionic. While `<sys/shm.h>` function declarations exist in API 26+ NDK headers, SysV IPC is disabled in default Android kernels (`CONFIG_SYSVIPC=n`). Software should use POSIX shared memory (`shm_open`), `memfd_create()`, or anonymous `mmap()`.
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

### Unified Bionic Sysroot Package (`pkgs/libs/bionic`)
`bionic-pkgs` consolidates core Bionic libc, NDK r27 platform sysroot headers (`<android/log.h>`, `<android/trace.h>`, `<android/sync.h>`, `<zlib.h>`, `<jni.h>`, etc.), architecture-specific platform stubs (`libz.so`, `liblog.so`, `libandroid.so`, etc.), and built-in compatibility shims into a single unified package `pkgs/libs/bionic` (`final.bionic`).

1. **GNU Linker Script Shims**: Provides `INPUT(-lc)` stubs directly inside `bionic.out/lib` for `libpthread.so`, `libpthread.a`, `librt.so`, `librt.a`, `libutil.so`, `libutil.a`, `libresolv.so`, `libresolv.a`, `libcrypt.so`, `libcrypt.a`.
2. **Header Shims via `#include_next`**: Wraps Bionic headers cleanly within the sysroot:
   - `<netinet/in.h>`: Injects `typedef uint32_t in_addr_t;`.
   - `<arpa/inet.h>`: Guarantees `<netinet/in.h>` is parsed before Bionic's `<arpa/inet.h>`.
   - `<sys/types.h>`: Guarantees POSIX `in_addr_t` is available in `<sys/types.h>`.
   - `<asm/stat.h>`: Uses `#pragma push_macro("__unused")` / `#undef __unused` to prevent macro collisions with Bionic `<sys/cdefs.h>`.
   - `<libintl.h>`: Provides standard no-op macro definitions for GNU gettext/libintl functions.
   - `<fnmatch.h>`: Provides fallback `#define FNM_EXTMATCH 0` for non-glibc systems.
3. **Platform Shared Library Stubs**: Unpacks official Android NDK platform headers and architecture-specific platform shared library stubs (`libz.so`, `liblog.so`, `libandroid.so`, etc.).

Packages no longer need to depend on standalone `android-prebuilts` or `bionic-compat` in `buildInputs`; the Bionic sysroot is supplied transparently by `stdenv`, and `zlib` maps directly to `final.bionic`.

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

### Enforcing PIE (`-fPIE -pie`), TLS (`-fno-emulated-tls`), and 16 KB Page Alignment (`-z max-page-size=16384`)
Rather than requiring every derivation to set repetitive compilation flags manually, `lib/bionic-compat.nix` defines canonical `bionicFlags` and injects `bionicFixupHook` globally into `stdenv.extraNativeBuildInputs`.

All target derivations built with `stdenv.mkDerivation` automatically receive:
- **`NIX_CFLAGS_COMPILE`**: `-nostdlibinc -fno-emulated-tls -D__BIONIC_NO_PAGE_SIZE_MACRO` (plus `-mtls-dialect=gnu` on x86_64)
- **`NIX_LDFLAGS`**: `-L${final.bionic.out}/lib -z max-page-size=16384 -z common-page-size=16384`

### Toolchain Role Isolation & Wrapper Hygiene
Nixpkgs cross-compilation uses role-based suffixing in CC wrappers to maintain clear separation between host and target build flags:
- **Host/Target Toolchains (`stdenv.cc`)**: Execute with role `_FOR_HOST` (`role_suffixes=('')`) and consume canonical unsuffixed `NIX_CFLAGS_COMPILE` and `NIX_LDFLAGS`.
- **Build Toolchains (`buildPackages.stdenv.cc` / `CC_FOR_BUILD`)**: Execute with role `_FOR_BUILD` and exclusively consume `NIX_CFLAGS_COMPILE_FOR_BUILD` and `NIX_LDFLAGS_FOR_BUILD`, completely ignoring unsuffixed variables.
- **Hook Propagation Rule**: Setup hooks injected into `stdenv.extraNativeBuildInputs` (which operate with `hostOffset = -1`) must **never** declare `propagatedBuildInputs` containing target libraries. If declared, Nixpkgs propagates those target libraries to the build machine environment and injects them into `NIX_LDFLAGS_FOR_BUILD` (a historical leak that caused Apple `ld64` on Darwin host builders to fail on target `-L` paths before commit f3ea460).

### Dynamic Linker Path (`/system/bin/linker64` / `/system/bin/linker`) & `$ORIGIN` RPATH
Android binaries locate their dynamic linker at:
- `/system/bin/linker64` (64-bit targets: `aarch64-android`, `x86_64-android`)
- `/system/bin/linker` (32-bit targets: `armv7a-android`, `i686-android`)

In `lib/bionic-compat.nix`, `bionicFixupHook` automatically ensures target ELF binaries have relative runpaths for device portability:
```nix
bionicFixup() {
  for output in ''${outputs:-out}; do
    local dir="''${!output:-}"
    if [ -n "$dir" ] && [ -d "$dir" ]; then
      find "$dir" -type f \( -perm -0100 -o -name "*.so*" \) -print0 | while IFS= read -r -d "" elf; do
        if [ -f "$elf" ] && [ "$(od -An -N4 -tx1 "$elf" 2>/dev/null | tr -d ' \n')" = "7f454c46" ]; then
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
   - **Resolution**: Layer `<netinet/in.h>`, `<arpa/inet.h>`, and `<sys/types.h>` shims in `pkgs/libs/bionic` using `#include_next` to define `in_addr_t` transparently.
4. **Macro Collisions with `__unused` in `<sys/cdefs.h>`**:
   - Bionic defines `#define __unused __attribute__((__unused__))` in `<sys/cdefs.h>`. When Linux UAPI headers like `<asm/stat.h>` declare fields named `__unused`, compilation fails with syntax errors.
   - **Resolution**: Wrap `<asm/stat.h>` in `pkgs/libs/bionic` with `#pragma push_macro("__unused")` / `#undef __unused` / `#include_next <asm/stat.h>` / `#pragma pop_macro("__unused")`.

### Case Study 2: `python3` & `libffi` (Minimal Standalone Runtime)
Python 3 on Android provides a standalone CLI scripting runtime and C interoperability via `ctypes`.

1. **Minimal Dependency Architecture**:
   - Upstream Linux Python distributions pull heavy dependency graphs (Tcl/Tk, readline, sqlite, gdbm, dbm, OpenSSL, libxcrypt, etc.).
   - For an efficient, portable Android runtime, optional modules are disabled (`--without-readline`, `--without-curses`, `--without-sqlite3`, `--without-gdbm`, `--without-dbm`, `--without-tkinter`, `--disable-test-modules`).
   - Hash algorithm support (`_hashlib` / `hashlib`) is fulfilled without OpenSSL via `--with-builtin-hashlib-hashes=md5,sha1,sha2,sha3,blake2` which compiles internal C implementations (HACL*).
   - Only `libffi` is retained as an external dependency to power `_ctypes` for native C library interaction.
2. **Cross-Compilation via `--with-build-python`**:
   - CPython 3.11+ cross-compilation requires a native host Python interpreter matching the target major and minor version (e.g., `buildPackages.python313`).
3. **Android System Logging (`<android/log.h>` & `liblog.so`)**:
   - Python's lifecycle initialization on Android includes `<android/log.h>` for `__android_log_write()`.
   - **Resolution**: `<android/log.h>` and `liblog.so` are supplied by `pkgs/libs/bionic` (provided transparently by `stdenv`), linking cleanly against Android's system `liblog.so`.
4. **Dynamic Page Sizes & 16 KB Kernel Compatibility**:
   - `bionicFlags` automatically passes `-D__BIONIC_NO_PAGE_SIZE_MACRO` in `NIX_CFLAGS_COMPILE` to avoid static page size assumptions across all packages.
   - `bionicFixupHook` enforces 16 KB page alignment across all `.so` C-extension modules (`lib-dynload/*.so`) and `libpython3.13.so`.
5. **Runtime Standard Library Resolution (`PYTHONHOME`)**:
   - When deployed via ADB to `/data/local/tmp/bionic-pkgs/python3`, the generated launcher wrapper script sets `export PYTHONHOME="$SCRIPT_DIR"` and `export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$SCRIPT_DIR/../lib:$LD_LIBRARY_PATH"`.

### Case Study 3: `elfutils` & Platform `libz.so` (Minimal ELF & DWARF Tool Suite)
`elfutils` provides core ELF manipulation (`libelf`, `eu-readelf`, `eu-nm`, `eu-strip`, `eu-size`, `eu-elfcmp`, `eu-elfcompress`, `eu-elflint`, `eu-elfclassify`, `eu-addr2line`, `eu-stack`, `eu-unstrip`) and DWARF debugging inspection (`libdw`, `libasm`).

1. **Minimizing Dependency Footprint & Leveraging Platform `libz.so`**:
   - Upstream Linux packaging of `elfutils` typically pulls heavy server daemon dependencies via `debuginfod` (`curl`, `sqlite`, `json-c`, `libmicrohttpd`, `libarchive`, `openssl`, `krb5`).
   - By disabling `debuginfod` (`--disable-debuginfod --disable-libdebuginfod`), NLS (`--disable-nls`), and the demangler (`--disable-demangler`), we eliminate transitively hundreds of megabytes of external dependencies.
   - Rather than compiling and staging a redundant `libz.so.1` binary, `pkgs/libs/bionic` provides official Google NDK `libz.so` stubs and `<zlib.h>` headers. The compiled binaries bind directly to Android's pre-installed, hardware-accelerated platform library (`/system/lib64/libz.so`), eliminating deployment staging overhead.
2. **Non-glibc Compatibility Shims (`argp`, `obstack`, `libintl`)**:
   - Android Bionic libc omits GNU `argp`, `obstack`, and `libintl` APIs.
   - `argp` and `obstack` are fulfilled via lightweight `argp-standalone` and `musl-obstack` packages.
   - `<libintl.h>` is provided as a standard no-op macro shim by `pkgs/libs/bionic`, eliminating external gettext dependencies.
3. **Pure Upstream 0.196 Build with Zero External Patches**:
   - `elfutils 0.196` incorporates upstream AArch64 floating-point register unpacking, `strndup` migration, and i386 relocation fixes, allowing pure upstream cross-compilation without vendor patches.
4. **Program Invocation Name Resolution**:
   - `elfutils` tools use `program_invocation_short_name` and `program_invocation_name` for error output.
   - In `lib/system.h`, these are redirected to Bionic's native `getprogname()` function.
5. **Compiler Flags & C++ Utility Decoupling**:
   - `-Werror` is stripped from Automake templates to prevent Clang warning differences from breaking cross-compilation.
   - The optional `srcfiles` C++ utility is decoupled from `bin_PROGRAMS` to avoid C++ standard library / libarchive requirements and ensure pure C builds.

### Case Study 4: `rizin` (Reverse Engineering Framework)
`rizin` is a UNIX-like reverse engineering framework and command-line toolset (`rizin`, `rz-asm`, `rz-ax`, `rz-bin`, `rz-diff`, `rz-find`, `rz-gg`, `rz-hash`, `rz-run`, `rz-sign`, `rz-ar`).

1. **Monolithic Binary Blob (`-Dblob=true`) & Multi-Call Dispatch**:
   - Upstream builds over 20 separate shared libraries. To eliminate dynamic library staging overhead on Android, we compile all modules statically into a single self-contained executable (`bin/rizin`) with dispatch symlinks (`rz-asm`, `rz-bin`, `rz-diff`, etc.) that multiplex commands based on `argv[0]`.
2. **Sandboxed Offline Cross-Compilation with Bundled Subprojects**:
   - Release archives bundle vetted dependencies in `subprojects/` (`capstone-next`, `pcre2`, `tree-sitter`, `xxhash`, `zydis`, etc.), with external system lookups disabled.
   - Host build generators (`sdb_gen`) require cross-native mirrors (`pcre2_cross_native`, `softfloat_cross_native`), prepared in `postPatch` for offline sandboxed builds.
3. **Disabling Unsupported Shared Memory IO Plugin (`disable-io-shm-on-android.patch`)**:
   - In `librz/io/p/io_shm.c`, the shared memory plugin implementation relies on POSIX `shm_open()`, legacy `/dev/ashmem`, or System V `shmat()`.
   - On modern Android, `shm_open()` is absent from Bionic, `ashmem` is removed from NDK headers and modern kernels, and SysV `shmat()` is disallowed by SELinux policies and disabled in default kernels (`CONFIG_SYSVIPC=n`).
   - We apply `disable-io-shm-on-android.patch` to guard the plugin implementation with `!defined(__ANDROID__)`, allowing `librz/io` to gracefully fall back to a clean stub descriptor without dead or broken syscall paths.
4. **Android x86_64 TLS Dialect limitation (`R_X86_64_TLSDESC`)**:
   - Bionic does not support `R_X86_64_TLSDESC` (relocation type 36) in Android API versions earlier than 35.
   - When `-fno-emulated-tls` is active, Clang defaults to TLSDESC on x86_64 Android targets unless `-mtls-dialect=gnu` is passed to force traditional GNU TLS.
5. **Upstream Android Meson Target Branching**:
   - Supplying `--cross-file` with `[host_machine] system = 'android'` in `preConfigure` activates Rizin's native upstream Android debug backends (`android_arm64.c`, `android_x86_64.c`) and skips the glibc-specific Linux coredump generator.
6. **Host Header Isolation (`-nostdlibinc`) & C23 `<stdbit.h>` Collision**:
   - The bundled `Zydis` subproject detects C23 `<stdbit.h>`, which leaked host glibc `/usr/include/stdbit.h` on modern build hosts and failed on missing `<bits/endian.h>`.
   - Globally injecting `-nostdlibinc` in `bionicFlags` restricts Clang to Bionic headers while preserving compiler builtins, ensuring hermetic cross-compilation.

### Case Study 5: `bcc` (BPF Compiler Collection & Target LLVM/Clang)
`bcc` provides dynamic kernel tracing, BPF C++ frontends, Python bindings, and introspection utilities (`bps`).

1. **Target LLVM & Clang C++ Toolchain Cross-Compilation**:
   - BCC embeds Clang/LLVM libraries (`libclang-cpp.so`, `libLLVM.so`) to compile runtime eBPF programs on-device.
   - LLVM and Clang are cross-compiled directly for Bionic targets (`-DLLVM_ENABLE_LIBCXX=ON -DLLVM_TARGETS_TO_BUILD="BPF;AArch64;X86;ARM"`), linking against target `libc++` and `compiler-rt`.
2. **Modern UAPI BTF Header Priority (`<linux/btf.h>`)**:
   - Older NDK kernel headers lack modern BTF enum definitions (e.g. `enum btf_func_linkage`).
   - When C++ headers parse `bpf/btf.h`, forward enum declarations fail in C++. Prepending `-isystem ${libbpf}/include` in `preConfigure` prioritizes `libbpf`'s modern UAPI headers over legacy Bionic sysroot kernel headers.
3. **Implicit Function Declarations in Introspection Utilities (`bzero`)**:
   - `introspection/bps.c` invoked legacy `bzero()` without `<strings.h>`.
   - Replaced with standard `memset()` via `postPatch` for strict ISO C99+ compliance.
4. **Fixing Pkgconfig Prefix Path Concatenation (`libbcc.pc`)**:
   - `libbcc.pc.in` defined `libdir=${exec_prefix}/@CMAKE_INSTALL_LIBDIR@`. Because Nix CMake sets `CMAKE_INSTALL_LIBDIR` to an absolute `/nix/store/...` path, this created invalid double slashes (`//`).
   - Rewritten to `libdir=''${prefix}/lib` in `postPatch`.
5. **Python 3 Runtime Bundling & Standalone Tool Launchers**:
   - On Android devices without `/usr/bin/env python`, BCC tools cannot run out-of-the-box.
   - BCC derivation copies the target `python3` binary and standard library into `$out/lib/python3.13` and installs wrapper scripts into `$out/bin/` (`execsnoop`, `opensnoop`, etc.) that configure `PYTHONHOME`, `PYTHONPATH`, and `LD_LIBRARY_PATH` and execute via `/system/bin/sh`.
6. **Bionic C Library Dynamic Loading in `ctypes` (`libc.so` vs `libc.so.6`/`librt.so.1`)**:
   - `src/python/bcc/perf.py` and `src/python/bcc/__init__.py` invoked `ctypes.CDLL('libc.so.6')` and `ctypes.CDLL('librt.so.1')`.
   - Patched via `postPatch` to reference Bionic's unified `libc.so`.
7. **macOS Host Isolation for Nested NATIVE Tablegen Builds (`--build-id=sha1`)**:
   - Nixpkgs sets `env.LDFLAGS = "-Wl,--build-id=sha1"` whenever the target (`hostPlatform`) is not Darwin.
   - When cross-compiling LLVM on a macOS build machine (`aarch64-darwin`), LLVM's CMake build invokes a nested CMake instance (`build/NATIVE`) using the host compiler (`clang-wrapper`) and Apple's linker (`cctools` / `ld64`) to build host `llvm-tblgen` and `llvm-config-native`.
   - This nested native CMake inherited the ambient `LDFLAGS="-Wl,--build-id=sha1"` environment variable, causing the host compiler check (`testCCompiler.c`) to fail on Darwin with `ld: unknown option: --build-id=sha1`.
   - **Resolution**: In `lib/bionic-compat.nix`, `libllvm` overrides `env.LDFLAGS = ""` to prevent ambient leakage into host subprojects, and passes `-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=sha1`, `-DCMAKE_MODULE_LINKER_FLAGS=-Wl,--build-id=sha1`, and `-DCMAKE_EXE_LINKER_FLAGS=-Wl,--build-id=sha1` explicitly in `cmakeFlags` for target binaries.

### Case Study 6: `bpftrace` & `bpftrace-static` (High-Level Dynamic Tracing Language & Tools)
`bpftrace` compiles high-level tracing scripts into eBPF bytecode via Clang/LLVM, attaching to kernel tracepoints, kprobes, uprobes, and intervals. We provide two builds:
- **`bpftrace` (Dynamic default)**: Built with `STATIC_LINKING=OFF` against shared LLVM/Clang and BCC libraries (`libLLVM.so`, `libclang-cpp.so`, `libbcc.so`, `libbpf.so`, etc.). Dynamic dependencies are synchronized from the package dependency closure into the device staging directory via `scripts/adb-push.sh` and resolved at runtime through relative `$ORIGIN/../lib` runpaths.
- **`bpftrace-static` (Standalone static)**: Built with `STATIC_LINKING=ON` embedding static LLVM, Clang components, BCC, and compression libraries into a self-contained executable.

1. **Standalone Semi-Static Architecture & Dual-Runtime Avoidance (`bpftrace-static`)**:
   - `bpftrace-static` is compiled with `-DSTATIC_LINKING=ON`, statically embedding LLVM 21, Clang AST/CodeGen/Rewriter components, BCC, libbpf, libdw, libelf, cereal, and `libc++`.
   - **Crucial C++ ODR Insight**: In hybrid static/dynamic configurations where `-static-libstdc++` is used alongside a dynamically loaded `libclang.so`, duplicate `std::locale` / `std::use_facet` Singletons clash at runtime, throwing `std::bad_cast`.
   - **Resolution**: Enabled `-DLIBCLANG_BUILD_STATIC=ON` in `lib/bionic-compat.nix` so Clang exports `libclang_static.a`. `bpftrace-static` links `libclang_static` into a unified static `libc++` runtime, dynamically binding **only** to Android's built-in platform C libraries (`libc.so`, `libm.so`, `libdl.so`, `libz.so`, `liblog.so`).
2. **Full Compression Integration (`LibLzma`, `LibBz2`, `libzstd`) & Binary Size Optimization**:
   - `elfutils` provides `libdw` and `libelf` with multi-format compression support (`--with-lzma`, `--with-bzlib`, `--with-zstd`, `--with-zlib`).
   - `bpftrace-static` leverages upstream `find_package(LibLzma)` and `find_package(LibBz2)` to statically bind `liblzma.a` and `libbz2.a`, and defines `LIBZSTD` to link `libzstd.a` for complete DWARF decompression on device.
   - Size optimization: Compiling with `-Wl,--gc-sections` and `--strip-all` eliminates unreferenced LLVM/Clang symbols and drops the standalone binary size by over 45 MB (~111 MB total). Dynamic dependencies bind strictly to Android platform libraries (`libc.so`, `libm.so`, `libdl.so`, `libz.so`, `liblog.so`).
3. **Clang Static Component Resolution & Transitive Dependency Unlinking**:
   - In static builds, `libbcc.a`'s object files reference Clang rewrite and AST utilities (`clang::Rewriter`, `clang::index::*`, `clang::ASTMatchFinder`, `clang::ASTReader`). Extended `src/ast/CMakeLists.txt` to link `clangRewrite`, `clangRewriteFrontend`, `clangIndex`, and `clangASTMatchers` static archives.
   - **Transitive Dependency Unlinking**: LLVM exports static target `LLVMSupport` with `INTERFACE_LINK_LIBRARIES "dl;-lpthread;m;ZLIB::ZLIB"`. In `-Bstatic` mode, CMake attempts to link these transitively as static archives, causing `ld.lld` errors (`cannot find -lpthread`, `attempted static link of dynamic object libz.so`). We use upstream's `unlink_transitive_dependency` helper to strip `ZLIB::ZLIB`, `-lpthread`, `dl`, and `m` from `LLVMSupport` and `${llvm_libs}`, linking them cleanly via `-Wl,-Bdynamic -ldl -lm -lz` at the final executable stage.
4. **Kernel Capability Definitions (`<linux/capability.h>`)**:
   - `src/run_bpftrace.cpp` checks for modern Linux capabilities (`CAP_BPF=39`, `CAP_PERFMON=38`, `CAP_CHECKPOINT_RESTORE=40`).
   - Android NDK r23 headers lack these definitions. Added a `<linux/capability.h>` shim to `pkgs/libs/bionic/` providing `#ifndef CAP_BPF ... #endif`.
5. **Embedded Standard Library via Host `xxd` (`Embed.cmake`)**:
   - `bpftrace` uses `xxd` to convert stdlib BPF scripts into C arrays embedded into the `bpftrace` binary. Added `xxd` to `nativeBuildInputs`.
6. **Standalone Companion Tools (`share/bpftrace/tools/*.bt`)**:
   - Generated wrapper scripts in `$out/bin/` (`execsnoop`, `opensnoop`, `runqlat`, `biosnoop`, `pidpersec`, `syscount`, `tcpconnect`, etc.) that execute via `/system/bin/sh`.

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
