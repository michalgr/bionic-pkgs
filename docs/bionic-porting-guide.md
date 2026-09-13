# Bionic Cross-Compilation & Porting Guide

Cross-compiling C/C++ applications for Android's **Bionic libc** differs significantly from standard GLIBC or Musl Linux environments. This guide documents Bionic quirks, patch patterns, target ABIs, and Nix-specific cross-compilation techniques used in `bionic-pkgs`.

---

## 1. Key Differences & Binary Requirements

1. **Combined `libc.so` (No `libpthread`, `librt`, `libutil`, `libresolv`, `libcrypt`)**:
   - In Bionic, POSIX threads (`pthread_*`), real-time timers (`clock_gettime`), dynamic loading (`dlopen`), and standard utilities are compiled directly into `libc.so`. (`libdl.so` and `libm.so` exist as stub libraries on device).
   - **Fix**: Strip `-lpthread -lrt -lutil -lresolv -lcrypt -lnsl` from `LDFLAGS` and build configurations, or provide GNU linker script stubs (`INPUT(libc.so)`) inside `bionic.out/lib`.

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
   - **Isolation & Header Cleanliness**: Prebuilt NDK C++ headers (`$dev/include/c++`) and libraries (`libc++*.so`, `libc++*.a`) are explicitly purged from the Bionic C sysroot (`lib/sysroot`), establishing a clean boundary between Bionic C / Linux UAPI headers and LLVM C++ standard library headers.
   - **Rationale**:
     - Eliminates opaque prebuilt binary blobs and stale headers from the build chain.
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

### Unified Bionic Sysroot Package (`lib/sysroot`)
`bionic-pkgs` consolidates core Bionic libc, NDK r27 platform sysroot headers (`<android/log.h>`, `<android/trace.h>`, `<android/sync.h>`, `<zlib.h>`, `<jni.h>`, etc.), architecture-specific platform stubs (`libz.so`, `liblog.so`, `libandroid.so`, etc.), and built-in compatibility shims into a single unified package `lib/sysroot` (`final.bionic`).

1. **GNU Linker Script Shims**: Provides `INPUT(libc.so)` stubs directly inside `bionic.out/lib` for `libpthread.so`, `libpthread.a`, `librt.so`, `librt.a`, `libutil.so`, `libutil.a`, `libresolv.so`, `libresolv.a`, `libcrypt.so`, `libcrypt.a`.
2. **Header Shims via `#include_next`**: Wraps Bionic headers cleanly within the sysroot:
   - `<netinet/in.h>`: Injects `typedef uint32_t in_addr_t;`.
   - `<arpa/inet.h>`: Guarantees `<netinet/in.h>` is parsed before Bionic's `<arpa/inet.h>`.
   - `<sys/types.h>`: Guarantees POSIX `in_addr_t` is available in `<sys/types.h>`.
   - `<asm/stat.h>`: Uses `#pragma push_macro("__unused")` / `#undef __unused` to prevent macro collisions with Bionic `<sys/cdefs.h>`.
   - `<libintl.h>`: Provides standard no-op macro definitions for GNU gettext/libintl functions.
   - `<fnmatch.h>`: Provides fallback `#define FNM_EXTMATCH 0` for non-glibc systems.
3. **Platform Shared Library Stubs**: Unpacks official Android NDK platform headers and architecture-specific platform shared library stubs (`libz.so`, `liblog.so`, `libandroid.so`, etc.).

Packages no longer need to depend on standalone `android-prebuilts` or `bionic-compat` in `buildInputs`; the Bionic sysroot is supplied transparently by `stdenv`, and `zlib` maps directly to `final.bionic`.

### Platform Semi-Static Linking Architecture
In `bionic-pkgs`, our architecture embraces a **Platform Semi-Static Linking Model**: third-party dependencies are statically linked into target binaries, while core platform dependencies (`libc`, `libm`, `libdl`, `libz`, `liblog`) dynamically bind to Android's `/system/lib64/` platform libraries.

To enforce this cleanly across static and dynamic build modes, `lib/sysroot` provides GNU linker script stubs (`.a` files) for platform libraries (`libc.a`, `libdl.a`, `libm.a`, `libz.a`, `liblog.a`, `libpthread.a`, etc.) containing exact `.so` filename directives (e.g. `INPUT(libc.so)`, `INPUT(libz.so)`, `INPUT(liblog.so)`).

**Why Exact Filenames over `-l` Search Flags (`INPUT(-lz)`)**:
Using search-flag syntax like `INPUT(-lz)` or `INPUT(-llog)` instructs the linker to run its standard library search algorithm. When a build system (such as CMake or Autotools) links in `-Bstatic` mode, the linker searches for `libz.a`, finds the stub file, and then evaluates `INPUT(-lz)`. Because `-Bstatic` is active, the search algorithm looks strictly for static archives (`libz.a`), re-encountering the same `.a` stub file. This causes linker loops or build failures with errors such as `attempted static link of dynamic object libz.so`. Specifying exact `.so` filenames (`INPUT(libz.so)`, `INPUT(liblog.so)`) forces the linker to directly resolve the dynamic platform object regardless of whether `-Bstatic` is enabled.

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
Rather than requiring every derivation to set repetitive compilation flags manually, `lib/overlays/stdenv.nix` (composed via `lib/bionic-compat.nix`) defines canonical `bionicFlags` and injects `bionicFixupHook` globally into `stdenv.extraNativeBuildInputs`.

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

`bionic-pkgs` uses a pure link-time RPATH model and has completely eliminated post-link `patchelf` binary rewriting. Rewriting ELF headers post-link risks disrupting 16 KB memory page alignment (`-z max-page-size=16384`) required on Android 15+.

In `lib/overlays/stdenv.nix`, link-time RPATH is automatically configured via `bionicFlags.ldflags` and `bionicFixupHook`:
- `bionicFlags.ldflags`: Emits `"-rpath"` `"\\$ORIGIN/../lib"` directly during linking, strictly hardening RPATH against Untrusted Search Path vulnerabilities (CWE-426/CWE-427).
- `bionicFixupHook`: Suppresses Nixpkgs automatic RPATH generation and self-rpath injection, prevents CMake from appending `$out/lib` during install, and patches generated `libtool` scripts to clear `hardcode_libdir_flag_spec`:
  ```bash
  export NIX_DONT_SET_RPATH=1
  export NIX_NO_SELF_RPATH=1
  export dontPatchELF=1
  export dontShrinkRPATH=1

  # Prevent CMake from injecting build-tree RPATHs or performing install-time RPATH rewrites
  addCmakeSkipRpath() {
    cmakeFlagsArray+=("-DCMAKE_SKIP_RPATH=ON")
  }
  preConfigureHooks+=(addCmakeSkipRpath)

  patchLibtoolRpath() {
    find . -name "libtool" -type f | while IFS= read -r lt; do
      if [ -f "$lt" ]; then
        sed -i 's/hardcode_libdir_flag_spec=.*/hardcode_libdir_flag_spec=""/g' "$lt"
        sed -i 's/hardcode_libdir_flag_spec_CXX=.*/hardcode_libdir_flag_spec_CXX=""/g' "$lt"
      fi
    done
  }
  postConfigureHooks+=(patchLibtoolRpath)
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
   - **Resolution**: Layer `<netinet/in.h>`, `<arpa/inet.h>`, and `<sys/types.h>` shims in `lib/sysroot` using `#include_next` to define `in_addr_t` transparently.
4. **Macro Collisions with `__unused` in `<sys/cdefs.h>`**:
   - Bionic defines `#define __unused __attribute__((__unused__))` in `<sys/cdefs.h>`. When Linux UAPI headers like `<asm/stat.h>` declare fields named `__unused`, compilation fails with syntax errors.
   - **Resolution**: Wrap `<asm/stat.h>` in `lib/sysroot` with `#pragma push_macro("__unused")` / `#undef __unused` / `#include_next <asm/stat.h>` / `#pragma pop_macro("__unused")`.

### Case Study 2: `python3`, `libffi`, `libedit` & `sqlite3` (Standalone Runtime & REPL)
Python 3 on Android provides a standalone CLI scripting runtime, C interoperability via `ctypes`, interactive REPL history, and SQLite database inspection.

1. **Minimal Dependency Architecture & Interactive REPL / SQLite Support**:
   - Upstream Linux Python distributions pull heavy dependency graphs (Tcl/Tk, gdbm, dbm, OpenSSL, libxcrypt, etc.).
   - Interactive line editing and command history are enabled using NetBSD `libedit` (`--with-readline=editline`) backed by `ncurses` (propagated via `propagatedBuildInputs = [ ncurses ];` to ensure `libncurses.so` is included in sysroot bundles).
   - Database inspection capabilities are enabled via `sqlite` (`--with-sqlite3`).
   - Heavy optional GUI and database modules remain disabled (`--without-curses`, `--without-gdbm`, `--without-dbm`, `--without-tkinter`, `--disable-test-modules`).
   - Hash algorithm support (`_hashlib` / `hashlib`) and SSL/TLS support (`_ssl`) are enabled via OpenSSL (`--with-openssl`).
   - `libffi` is retained to power `_ctypes` for native C library interaction.
2. **NetBSD `libedit` Bionic Porting Shims**:
   - `libedit` requires specific Bionic compiler flags (`NIX_CFLAGS_COMPILE = "-D__STDC_ISO_10646__=200009L -DHAVE_SIZE_MAX -DNBBY=8"`):
     - `-D__STDC_ISO_10646__=200009L`: Bionic `wchar_t` uses UTF-32/ISO 10646, but `<wchar.h>` lacks the macro definition.
     - `-DHAVE_SIZE_MAX`: Prevents `sys.h` from redefining `SIZE_MAX`, which conflicts with Bionic `<stdint.h>`.
     - `-DNBBY=8`: Bionic `<sys/param.h>` lacks the BSD `NBBY` (Number of Bits per BYte) macro required by `src/vis.c`.
3. **Cross-Compilation via `--with-build-python`**:
   - CPython 3.11+ cross-compilation requires a native host Python interpreter matching the target major and minor version (e.g., `buildPackages.python313`).
4. **Android System Logging (`<android/log.h>` & `liblog.so`)**:
   - Python's lifecycle initialization on Android includes `<android/log.h>` for `__android_log_write()`.
   - **Resolution**: `<android/log.h>` and `liblog.so` are supplied by `lib/sysroot` (provided transparently by `stdenv`), linking cleanly against Android's system `liblog.so`.
5. **Dynamic Page Sizes & 16 KB Kernel Compatibility**:
   - `bionicFlags` automatically passes `-D__BIONIC_NO_PAGE_SIZE_MACRO` in `NIX_CFLAGS_COMPILE` to avoid static page size assumptions across all packages.
   - `bionicFixupHook` enforces 16 KB page alignment across all `.so` C-extension modules (`lib-dynload/*.so`) and `libpython3.13.so`.
6. **Runtime Standard Library Resolution (`PYTHONHOME`) & Scoped Extension RPATH**:
   - When deployed via ADB to `/data/local/tmp/bionic-pkgs/python3`, the generated launcher wrapper script sets `export PYTHONHOME="$SCRIPT_DIR"`.
   - CPython extension modules located in `prefix/lib/python3.13/lib-dynload/` require an additional `$ORIGIN/../..` runpath to locate `libpython3.13.so` and `libffi.so` in `prefix/lib`.
   - In `pkgs/runtime/python3/default.nix`, `Makefile.pre.in` is patched via `postPatch` to append `-Wl,-rpath,\$ORIGIN/../..` strictly to `MODULE_LDFLAGS_SHARED`, ensuring `$ORIGIN/../..` remains strictly confined within `prefix/lib`.

### Case Study 3: `elfutils` & Platform `libz.so` (Minimal ELF & DWARF Tool Suite)
`elfutils` provides core ELF manipulation (`libelf`, `eu-readelf`, `eu-nm`, `eu-strip`, `eu-size`, `eu-elfcmp`, `eu-elfcompress`, `eu-elflint`, `eu-elfclassify`, `eu-addr2line`, `eu-stack`, `eu-unstrip`) and DWARF debugging inspection (`libdw`, `libasm`).

1. **Minimizing Dependency Footprint & Leveraging Platform `libz.so`**:
   - Upstream Linux packaging of `elfutils` typically pulls heavy server daemon dependencies via `debuginfod` (`curl`, `sqlite`, `json-c`, `libmicrohttpd`, `libarchive`, `openssl`, `krb5`).
   - By disabling `debuginfod` (`--disable-debuginfod --disable-libdebuginfod`), NLS (`--disable-nls`), and the demangler (`--disable-demangler`), we eliminate transitively hundreds of megabytes of external dependencies.
   - Rather than compiling and staging a redundant `libz.so.1` binary, `lib/sysroot` provides official Google NDK `libz.so` stubs and `<zlib.h>` headers. The compiled binaries bind directly to Android's pre-installed, hardware-accelerated platform library (`/system/lib64/libz.so`), eliminating deployment staging overhead.
2. **Non-glibc Compatibility Shims (`argp`, `obstack`, `libintl`)**:
   - Android Bionic libc omits GNU `argp`, `obstack`, and `libintl` APIs.
   - `argp` and `obstack` are fulfilled via lightweight `argp-standalone` and `musl-obstack` packages.
   - `<libintl.h>` is provided as a standard no-op macro shim by `lib/sysroot`, eliminating external gettext dependencies.
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
5. **Decoupled Python Module & Hardened Runtime Resolution**:
   - Rather than embedding a duplicate target Python 3 interpreter and standard library inside BCC's output `$out`, `bcc` installs its pure Python module into `$out/lib/python3.13/site-packages/bcc/`.
   - Tool wrappers in `$out/bin/` (`execsnoop`, `opensnoop`, etc.) strictly enforce fail-closed Python interpreter resolution confined strictly to `$BASE_DIR`: checking explicit `BCC_PYTHON_BIN` administrative override or staged sysroot Python (`$BASE_DIR/bin/python3`). Sibling directory traversal (`$BASE_DIR/../python3/bin/python3`), fallbacks to mutable `run.sh`, or untrusted ambient `PATH` (`python3`) are completely eliminated (CWE-426/CWE-427). Disjoint push deployments (separate `/data/local/tmp/bionic-pkgs/bcc` and `.../python3` directories) require explicit intent via setting `BCC_PYTHON_BIN=/path/to/python3`. If no valid interpreter is found, wrappers exit with status 1 and write a clear error message to stderr.
   - Wrappers set `PYTHONPATH="$BASE_DIR/lib/python3.13/site-packages"` hermetically without appending ambient `${PYTHONPATH}`, preventing untrusted module injection during elevated execution (root / CAP_BPF).
   - To prevent untrusted library traversal and dynamic linker search path injection vulnerabilities (CWE-426), ambient `LD_LIBRARY_PATH` environment variable exports have been completely eliminated across all wrapper scripts, launcher generators, and test runners in favor of hermetic relative `DT_RUNPATH` resolution.
6. **Hermetic `libbcc.so` Dynamic Loading via `ctypes`**:
   - In `src/python/bcc/libbcc.py`, `libbcc.so` loading was patched via `postPatch` to resolve `libbcc.so` relative to `__file__`:
     ```python
     _rel_path = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "libbcc.so"))
     _so_path = _rel_path if os.path.isfile(_rel_path) else "libbcc.so.0"
     lib = ct.CDLL(_so_path, use_errno=True)
     ```
   - Because `libbcc.so` contains `DT_RUNPATH = $ORIGIN/../lib` (pointing to `$out/lib`), passing its explicit path to `dlopen()` allows Bionic's dynamic linker (`/system/bin/linker64`) to automatically resolve all transitive dependencies (`libbpf.so`, `libelf.so`, etc.) without relying on ambient or insecure `LD_LIBRARY_PATH` environment variables.
7. **Bionic C Library Dynamic Loading in `ctypes` (`libc.so` vs `libc.so.6`/`librt.so.1`)**:
   - `src/python/bcc/perf.py` and `src/python/bcc/__init__.py` invoked `ctypes.CDLL('libc.so.6')` and `ctypes.CDLL('librt.so.1')`.
   - Patched via `postPatch` to reference Bionic's unified `libc.so`.
8. **macOS Host Isolation for Nested NATIVE Tablegen Builds**:
   - `libllvm` and `libclang` are standalone packages under `pkgs/libs/llvm/` (`libllvm.nix`, `libclang.nix`). Rather than running error-prone nested native builds during cross-compilation, they set `-DLLVM_NATIVE_BUILD=OFF` and consume prebuilt native host tools (`llvm-tblgen`, `clang-tblgen`) directly from `pkgs/libs/llvm/tblgen.nix`.

### Case Study 6: `bpftrace` & `bpftrace-static` (High-Level Dynamic Tracing Language & Tools)
`bpftrace` compiles high-level tracing scripts into eBPF bytecode via Clang/LLVM, attaching to kernel tracepoints, kprobes, uprobes, and intervals. We provide two builds:
- **`bpftrace` (Dynamic default)**: Built with `STATIC_LINKING=OFF` against shared LLVM/Clang and BCC libraries (`libLLVM.so`, `libclang-cpp.so`, `libbcc.so`, `libbpf.so`, etc.). Dynamic dependencies are synchronized from the package dependency closure into the device staging directory via `scripts/adb-push.sh` and resolved at runtime through relative `$ORIGIN/../lib` runpaths.
- **`bpftrace-static` (Standalone static)**: Built with `STATIC_LINKING=ON` embedding static LLVM, Clang components, BCC, and compression libraries into a self-contained executable.

1. **Standalone Semi-Static Architecture & Dual-Runtime Avoidance (`bpftrace-static`)**:
   - `bpftrace-static` is compiled with `-DSTATIC_LINKING=ON`, statically embedding LLVM 19, Clang AST/CodeGen/Rewriter components, BCC, libbpf, libdw, libelf, cereal, and `libc++`.
   - **Crucial C++ ODR Insight**: In hybrid static/dynamic configurations where `-static-libstdc++` is used alongside a dynamically loaded `libclang.so`, duplicate `std::locale` / `std::use_facet` Singletons clash at runtime, throwing `std::bad_cast`.
   - **Resolution**: Enabled `-DLIBCLANG_BUILD_STATIC=ON` in `pkgs/libs/llvm/libclang.nix` so Clang exports `libclang_static.a`. `bpftrace-static` links `libclang_static` into a unified static `libc++` runtime, dynamically binding **only** to Android's built-in platform C libraries (`libc.so`, `libm.so`, `libdl.so`, `libz.so`, `liblog.so`).
2. **Full Compression Integration (`LibLzma`, `LibBz2`, `libzstd`) & Binary Size Optimization**:
   - `elfutils` provides `libdw` and `libelf` with multi-format compression support (`--with-lzma`, `--with-bzlib`, `--with-zstd`, `--with-zlib`).
   - `bpftrace-static` leverages upstream `find_package(LibLzma)` and `find_package(LibBz2)` to statically bind `liblzma.a` and `libbz2.a`, and defines `LIBZSTD` to link `libzstd.a` for complete DWARF decompression on device.
   - Size optimization: Compiling with `-Wl,--gc-sections` and `--strip-all` eliminates unreferenced LLVM/Clang symbols and drops the standalone binary size by over 45 MB (~111 MB total). Dynamic dependencies bind strictly to Android platform libraries (`libc.so`, `libm.so`, `libdl.so`, `libz.so`, `liblog.so`).
3. **Clang Static Component Resolution & Transitive Dependency Unlinking**:
   - In static builds, `libbcc.a`'s object files reference Clang rewrite and AST utilities (`clang::Rewriter`, `clang::index::*`, `clang::ASTMatchFinder`, `clang::ASTReader`). Extended `src/ast/CMakeLists.txt` to link `clangRewrite`, `clangRewriteFrontend`, `clangIndex`, and `clangASTMatchers` static archives.
   - **Transitive Dependency Unlinking**: LLVM exports static target `LLVMSupport` with `INTERFACE_LINK_LIBRARIES "dl;-lpthread;m;ZLIB::ZLIB"`. In `-Bstatic` mode, CMake attempts to link these transitively as static archives, causing `ld.lld` errors (`cannot find -lpthread`, `attempted static link of dynamic object libz.so`). We use upstream's `unlink_transitive_dependency` helper to strip `ZLIB::ZLIB`, `-lpthread`, `dl`, and `m` from `LLVMSupport` and `${llvm_libs}`, linking them cleanly via `-Wl,-Bdynamic -ldl -lm -lz` at the final executable stage.
4. **Kernel Capability Definitions (`<linux/capability.h>`)**:
   - `src/run_bpftrace.cpp` checks for modern Linux capabilities (`CAP_BPF=39`, `CAP_PERFMON=38`, `CAP_CHECKPOINT_RESTORE=40`).
   - Android NDK r23 headers lack these definitions. Added a `<linux/capability.h>` shim to `lib/sysroot/` providing `#ifndef CAP_BPF ... #endif`.
5. **Embedded Standard Library via Host `xxd` (`Embed.cmake`)**:
   - `bpftrace` uses `xxd` to convert stdlib BPF scripts into C arrays embedded into the `bpftrace` binary. Added `xxd` to `nativeBuildInputs`.
6. **Standalone Companion Tools (`share/bpftrace/tools/*.bt`)**:
   - Generated wrapper scripts in `$out/bin/` (`execsnoop`, `opensnoop`, `runqlat`, `biosnoop`, `pidpersec`, `syscount`, `tcpconnect`, etc.) that execute via `/system/bin/sh` without setting `LD_LIBRARY_PATH`, relying on `bpftrace`'s embedded relative `DT_RUNPATH` (`$ORIGIN/../lib`).

### Case Study 7: `lldb` & `lldb-server` (LLVM Debugger & Companion Server)
`lldb` provides high-performance native debugging, target image inspection, breakpoint management, and process control on Android 14+ (Bionic libc) alongside companion `lldb-server` and `lldb-dap`.

1. **Host TableGen Suite (`tblgen`) Integration**:
   - Upstream LLDB standalone cross-compilation attempts to build host tablegen tools using a nested CMake NATIVE subproject (`llvm_create_cross_target`). In Nix cross-compilation, this subproject incorrectly inherits target sysroot flags and fails.
   - LLDB skips this nested subproject if `LLDB_TABLEGEN_EXE` is set and `LLVM_NATIVE_BUILD` is set to `OFF`.
   - Host TableGen tools (`llvm-tblgen`, `clang-tblgen`, `lldb-tblgen`) are supplied directly by our native host `tblgen` package (`pkgs/libs/llvm/tblgen.nix`).
   - We pass `-DLLVM_NATIVE_TOOL_DIR=${tblgen}/bin`, `-DLLVM_TABLEGEN=${tblgen}/bin/llvm-tblgen`, `-DCLANG_TABLEGEN=${tblgen}/bin/clang-tblgen`, and `-DLLDB_TABLEGEN=${tblgen}/bin/lldb-tblgen` to target LLDB.
2. **NetBSD `libedit` Integration on Android**:
   - `include/lldb/Host/Editline.h` guards `#include <histedit.h>` with `#if !defined(_WIN32) && !defined(__ANDROID__)`.
   - Substituted `#if !defined(_WIN32) && !defined(__ANDROID__)` with `#if !defined(_WIN32)` in `postPatch` to enable NetBSD `libedit` command-line history and interactive editing on Android.
3. **Build-Time Python for `SBLanguages.h` Generation**:
   - When `-DLLDB_ENABLE_PYTHON=OFF`, LLDB still requires a build-time Python interpreter to generate `SBLanguages.h` from LLVM's `Dwarf.def` via `generate-sbapi-dwarf-enum.py`.
   - Upstream `source/API/CMakeLists.txt` already references `COMMAND "${Python3_EXECUTABLE}"`.
   - We add `buildPackages.python3` to `nativeBuildInputs` and pass `"-DPython3_EXECUTABLE=${buildPackages.python3.interpreter}"` in `cmakeFlags` without source patching.
4. **Android Host Platform Detection**:
   - We pass `(lib.cmakeBool "ANDROID" true)` in `cmakeFlags`.
   - We substitute `if (CMAKE_SYSTEM_NAME MATCHES "Android")` with `if (ANDROID OR CMAKE_SYSTEM_NAME MATCHES "Android")` in `source/Host/CMakeLists.txt` so `android/HostInfoAndroid.cpp` is properly included when cross-compiling.
5. **Zero `patchelf` & Zero `postFixup` RPATH Preservation**:
   - Link-time RPATH is automatically configured to `-rpath $ORIGIN/../lib` by `bionicFlags.ldflags` in `lib/bionic-compat.nix`.
   - To prevent CMake from rewriting or leaking host `/nix/store/...` paths during installation, we pass `-DLLDB_NO_INSTALL_DEFAULT_RPATH=ON` and `-DCMAKE_SKIP_RPATH=ON` in `cmakeFlags`.
   - Passing `-DCMAKE_SKIP_RPATH=ON` suppresses CMake's internal build-tree RPATH generation and install-time RPATH rewriting, eliminating malformed leading colons (`[:$ORIGIN/../lib]`) and ensuring the binary cleanly relies on the pure link-time `-rpath $ORIGIN/../lib` passed by `bionicFlags.ldflags`.
6. **Python Scripting Enablement & Cross-Compilation Variables**:
   - Enabling Python scripting (`-DLLDB_ENABLE_PYTHON=ON`) requires SWIG (`buildPackages.swig`) to generate `LLDBWrapPython.cpp` at build time.
   - Target Python headers and shared library paths (`Python3_INCLUDE_DIR`, `Python3_LIBRARY`, `Python3_LIBRARIES`) are supplied to CMake's `FindPython3` module so `liblldb.so` dynamically links against target `libpython3.13.so`.
   - Upstream LLDB cross-compilation checks require setting three mandatory CMake path variables:
     - `-DLLDB_PYTHON_RELATIVE_PATH=lib/python3.13/site-packages`
     - `-DLLDB_PYTHON_EXE_RELATIVE_PATH=bin/python3`
     - `-DLLDB_PYTHON_EXT_SUFFIX=.cpython-313-<arch>-linux-android.so`
   - Adding `python3` to LLDB's `buildInputs` ensures `adb-push.sh` and sysroot bundles automatically aggregate `libpython3.13.so` and Python standard library paths into the device deployment directory.

### Case Study 8: `openssl` (OpenSSL Cryptographic & SSL/TLS Toolkit)
`openssl` provides shared cryptographic libraries (`libssl.so`, `libcrypto.so`), engines, providers (`legacy.so`), and the `openssl` command-line utility for Android.

1. **Disabling Unsupported Kernel Extensions (`no-ktls`, `no-afalgeng`)**:
   - Kernel TLS (`enable-ktls`) requires Linux kernel socket structures and headers that are incomplete/unsupported in Android Bionic (`<sys/socket.h>` and `include/internal/ktls.h`).
   - The Linux AF_ALG crypto engine (`afalgeng`) is unsupported in standard Android userspace.
   - We pass `no-ktls` and `no-afalgeng` to `./Configure` to disable these unsupported features.
2. **Architecture Target Selection**:
   - OpenSSL's custom `./Configure` script requires exact target platform strings rather than GNU triple `--host`:
     - `aarch64-android`: `linux-aarch64` (activates hardware-accelerated ARMv8 NEON and Crypto extensions)
     - `x86_64-android`: `linux-x86_64`
     - `armv7a-android`: `linux-armv4`
     - `i686-android`: `linux-x86`
     - `riscv64-android`: `linux64-riscv64`
   - Setting `configurePlatforms = [ ];` and `dontAddStaticConfigureFlags = true;` prevents Nix from passing invalid `--build` or `--host` flags to `./Configure`.
3. **Android Shell Wrapper for `c_rehash`**:
   - Upstream OpenSSL generates `c_rehash` as a Perl script. On Android, Perl is absent from the device system PATH.
   - We replace `c_rehash` with an Android-native `/system/bin/sh` shell script:
     ```sh
     #!/system/bin/sh
     exec "$(dirname "$0")/openssl" rehash "$@"
     ```
4. **Python 3 Integration**:
   - Adding `openssl` to Python 3's `buildInputs` and `--with-openssl=${openssl.dev or openssl}` builds CPython extension modules `_ssl.so` and `_hashlib.so`.
   - In `_ssl.cpython-*.so`, relative runpath `-Wl,-rpath,$ORIGIN/../..` resolves `libssl.so` and `libcrypto.so` in `lib/`.

### Case Study 9: `gdb` & `gdbserver` (GNU Debugger with Python 3)
`gdb` (v17.2) and companion `gdbserver` provide full target debugging, breakpoint control, inferior process execution, remote debugging, and Python 3 scripting integration on Android 14+ (Bionic libc).

1. **Host Build Tool Compiler Isolation (`CC_FOR_BUILD`)**:
   - GDB builds an internal build-time document tool (`bfd/doc/chew.c`) using the build host C compiler (GCC/Clang).
   - Because `bionicFixupHook` exports Clang-specific Bionic flags (`-nostdlibinc`, `-fno-emulated-tls`) into `NIX_CFLAGS_COMPILE`, host `gcc` fails on `x86_64-linux` with unknown flag errors.
   - **Resolution**: Generate a localized executable wrapper at `$PWD/build-bin/build-cc` during `preConfigure`:
     ```sh
     mkdir -p "$PWD/build-bin"
     cat > "$PWD/build-bin/build-cc" << 'BUILD_CC_EOF'
     #!/bin/sh
     NIX_CFLAGS_COMPILE="" NIX_LDFLAGS="" exec "${buildPackages.stdenv.cc}/bin/cc" "$@"
     BUILD_CC_EOF
     chmod +x "$PWD/build-bin/build-cc"
     configureFlagsArray+=("CC_FOR_BUILD=$PWD/build-bin/build-cc")
     makeFlagsArray+=("CC_FOR_BUILD=$PWD/build-bin/build-cc")
     ```
2. **Cross Python 3 Helper Script (`python-config-cross.sh`)**:
   - GDB's `./configure` expects `--with-python=<path>` to point to a configuration script.
   - Generated a cross helper script `python-config-cross.sh` in `preConfigure` returning `--includes` (`-I${python3}/include/python3.13`), `--ldflags` (`-L${python3}/lib -lpython3.13`), and `--exec-prefix` (`${python3}`).
3. **Bionic Compatibility Patches**:
   - **Overloaded `::open` Template Deduction**: In `gdbsupport/eintr.h`, replaced `gdb::handle_eintr (-1, ::open, pathname, flags)` with an explicit `do { errno = 0; ret = ::open(pathname, flags); } while (ret == -1 && errno == EINTR);` loop.
   - **Android Paths**: Patched `/tmp` to `/data/local/tmp` in `gdbsupport/pathstuff.cc` and `gdb/compile/compile.c`, and `/bin/sh` to `/system/bin/sh`.
   - **Signal State Warning**: Suppressed preinstalled signal warning on Android in `gdbsupport/signals-state-save-restore.cc`.
   - **Job Control**: Replaced `setpgid(getpid(), getpid())` with `setpgid(0, 0)` in `gdbsupport/job-control.cc` to support non-root execution.
   - **Dynamic 16 KB Page Size**: Defined `PAGE_SIZE` as `((size_t) sysconf(_SC_PAGESIZE))` in `gdb/nat/linux-btrace.c`.
   - **Solib Search Path**: Configured default `solib_search_path` to `/system/lib64:/system/vendor/lib64` (or 32-bit counterpart) in `gdb/solib.c`.
   - **Auxv Override**: Disabled `*-android*)` auxv override in `gdbserver/configure`.
   - **x86_64 Register Assertions**: Guarded `FS < ELF_NGREG` and `GS < ELF_NGREG` register index assertions under `#ifndef __ANDROID__` in `gdb/amd64-linux-nat.c`.
4. **Gnulib Fortify Header Collision**:
   - Set `env.NIX_CFLAGS_COMPILE = "-Wno-format-nonliteral -Wno-unused-function -D__USE_FORTIFY_LEVEL=0"` to prevent Gnulib and Bionic stdio fortify collisions.

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
   nix run .#push-aarch64-android-strace

   # Or manual transfer:
   adb push result/bin/strace /data/local/tmp/
   adb shell chmod 755 /data/local/tmp/strace
   adb shell /data/local/tmp/strace -V
   ```

---

## 7. Standardized Archive & Runtime Bundle Generation

For deploying aggregated runtime environments (sysroots) or standalone binary archives, `bionic-pkgs` provides standardized build helpers and staging scripts:

1. **`makeArchive` (`pkgs/build-support/make-archive`)**:
   Creates reproducible `.tar.gz` or `.tar.zst` tarballs from a directory or derivation output with bit-for-bit determinism flags (`--owner=0 --group=0 --numeric-owner --mtime='@1' --sort=name`).

2. **`scripts/stage-runtime.sh`**:
   Stages binary executables, shared libraries, and runtime share assets while stripping non-runtime artifacts (`*.a`, `*.la`, `*.o`, `pkgconfig/`, `cmake/`, `man`, `doc`). Automatically fixes linker script stubs and generates entrypoint launchers.

3. **`runtimeArchive` (`pkgs/build-support/runtime-archive`)**:
   High-level derivation helper that computes dependency closures, strips build-time Bionic stubs, stages runtime files via `stage-runtime.sh`, and outputs a deterministic archive using `makeArchive`.
