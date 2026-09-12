# System Architecture Specification

## 1. Vision & Core Philosophy

`bionic-pkgs` is designed to be the definitive, reproducible package collection and cross-compilation matrix for Android (Bionic libc) target binaries.

### Why standard Android NDK is insufficient
Cross-compiling standalone Linux CLI tools and diagnostic utilities for Android with the standard Google NDK is notoriously painful:
1. **Transitive dependencies are hard**: Manually building and linking non-trivial dependency chains (e.g. `libffi`, `readline`, `openssl`) without a package manager is brittle and time-consuming.
2. **Dialing cross-compilation options is tedious**: Finding the right combination of target triples, sysroot flags, PIE enforcement, and 16 KB page alignment requires constant trial and error.
3. **No ARM64 Linux NDK**: Google NDK does not provide official toolchains for `aarch64-linux` hosts (e.g. Docker/containers on Apple Silicon, AWS Graviton, Asahi Linux).
4. **Bionic libc adjustments**: Bionic differs from glibc/musl (no separate `libpthread`/`librt`, missing POSIX symbols, unified `libc.so`), requiring targeted patches and shims.
5. **Stateful output directories & lack of reproducibility**: Imperative shell scripts pollute host environments and produce non-reproducible artifacts.

### The Nix Approach
By leveraging **Nix Flakes**, `bionic-pkgs` turns cross-compilation into pure functional evaluation:
- Toolchains, sysroots (Bionic headers, kernel headers), and dependencies are declared as Nix derivations.
- Cross-compiling on **Apple Silicon Macs** (`aarch64-darwin`) or **Linux ARM64 environments** (`aarch64-linux`) works natively because Nix builds target-aware cross-compilers directly on the host platform.
- Builds are fully hermetic, reproducible, and cacheable.

---

## 2. Platform Matrix

### Supported Host Architectures (`buildPlatform` / `hostPlatform`)
Host outputs are generated dynamically via `bionicLib.eachSystem bionicLib.supportedSystems`:
| Host Flake System ID | Architecture | OS | Typical Hardware / Environments |
| :--- | :--- | :--- | :--- |
| `aarch64-linux` | ARM64 (64-bit) | Linux | Docker/Podman/OrbStack/Lima containers on Apple Silicon Macs, AWS Graviton, Asahi Linux, Raspberry Pi 4/5 |
| `aarch64-darwin` | ARM64 (64-bit) | macOS | Apple Silicon (M1/M2/M3/M4 Macs) |
| `x86_64-linux` | x86_64 (64-bit) | Linux | Standard Intel/AMD Linux Workstations & CI Runners |

### Supported Android Target ABIs (`targetPlatform`)
| Target Key | Nixpkgs Config Triple | Clang/LLVM Triple | Android ABI | Dynamic Linker | Default API Level | Priority |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `aarch64-android` | `aarch64-unknown-linux-android` | `aarch64-linux-android` | `arm64-v8a` (64-bit) | `/system/bin/linker64` | API 34 (Android 14+) | **Tier 1 (Primary)** |
| `x86_64-android` | `x86_64-unknown-linux-android` | `x86_64-linux-android` | `x86_64` (64-bit) | `/system/bin/linker64` | API 34 (Android 14+) | **Tier 1** |
| `armv7a-android` | `armv7a-unknown-linux-androideabi` | `armv7a-linux-androideabi` | `armeabi-v7a` (32-bit) | `/system/bin/linker` | API 34 (Android 14+) | **Tier 2** |
| `i686-android` | `i686-unknown-linux-android` | `i686-linux-android` | `x86` (32-bit) | `/system/bin/linker` | API 34 (Android 14+) | **Tier 2** |

---

## 3. Toolchain & Nixpkgs Integration Strategy

`bionic-pkgs` builds upon Nixpkgs' native cross-compilation infrastructure (`pkgs.pkgsCross.<target>`):

```
                         ┌──────────────────────────────────────────┐
                         │              bionic-pkgs                 │
                         └────────────────────┬─────────────────────┘
                                              │
                                              ▼
                             ┌──────────────────────────────────┐
                             │   Pure Nixpkgs Cross-Toolchain   │
                             │     (pkgs.pkgsCross.<target>)    │
                             └────────────────┬─────────────────┘
                                              │
                                              ├── Host-native Clang/LLVM Cross-Compiler
                                              ├── Hermetic Bionic libc & Linux kernel headers
                                              ├── Nixpkgs stdenv cross-infrastructure & shims
                                              └── Declarative C/C++ dependency composition
```

### Toolchain Details & Sysroot Provenance
- **Bionic Headers & Sysroot**: In Nixpkgs, target Android sysroots hermetically package the official Bionic libc headers, CRT startup files, and kernel headers derived from Android platform sysroots.
- **Host-Native Cross-Compilers**: Nix compiles LLVM/Clang directly for the host platform (`aarch64-linux`, `aarch64-darwin`, `x86_64-linux`), eliminating reliance on Google's prebuilt host binaries.
- **C++ Standard Library (STL) Implementation**:
  - `bionic-pkgs` does **not** use the standard prebuilt Google NDK `libc++_shared.so` or `libc++_static.a` binaries.
  - Instead, `bionic-pkgs` compiles LLVM's modern `libc++` and `libc++abi` directly from source against Bionic libc with native ELF TLS (`-fno-emulated-tls`).
  - **Why this approach?**:
    1. **Hermeticity & Reproducibility**: Builds the entire C++ standard library deterministically from source matching the exact LLVM version used by the cross-compiler.
    2. **Modern C++ Standards**: Unlocks complete C++20, C++23, and C++26 language and library features without being restricted by NDK release cadence.
    3. **16 KB Memory Page Alignment**: Ensures `libc++.so` and all C++ runtime objects are linked with `-z max-page-size=16384` for Android 15+ 16 KB kernel compatibility.
    4. **Hardening & Unwinding**: Leverages LLVM's modern unwinder (`llvm-libunwind`) built from source and enables configurable standard library hardening modes (`_LIBCPP_HARDENING_MODE`).

---

## 4. Package Organization & Taxonomy

Packages are organized in `pkgs/` and `tests/` by functional category:

```
bionic-pkgs/
├── flake.nix
├── lib/
│   ├── default.nix
│   ├── bionic-compat.nix
│   └── overlays/
│       ├── sysroot.nix
│       ├── stdenv.nix
│       └── llvm.nix
├── scripts/
│   ├── stage-runtime.sh      # Factored runtime staging, pruning, and launcher generation
│   ├── generate-launcher.sh  # Android runtime entrypoint launcher script generator
│   ├── ci-fast-smoke-test.sh # Fast smoke triad deployment and test runner
│   ├── ci-emulator-test.sh   # Sysroot and static bpftrace integration runner
│   └── check-elf.sh          # ELF alignment, dynamic linker, and dependency audit
├── tests/
│   ├── lib/                  # Test framework (common.sh, adb-helpers.sh)
│   ├── tools/                # Codified test scripts for each tool (test-<tool>.sh)
│   ├── test-integration.sh   # Cross-tool cohabitation integration test suite
│   └── run-device-tests.sh   # Master test orchestrator
├── pkgs/
│   ├── default.nix
│   ├── build-support/   # Verification hooks and archive builders (make-archive, runtime-archive)
│   ├── bundles/         # Aggregated sysroot and static tool archive derivations
│   ├── diagnostics/     # Debuggers, syscall monitors, crash dump tools (strace, gdb, lldb)
│   ├── tracing/         # eBPF tools, kernel probes, performance analyzers (bcc, bpftrace)
│   ├── reversing/       # Disassemblers, binary analysis tools (radare2, rizin)
│   ├── runtime/         # Interpreters, language engines (python3)
│   ├── core/            # Core system utilities (tree, file, tmux, bash)
│   └── libs/            # Shared libraries, polyfills (bionic, libffi, elfutils, libbpf)
```

---

## 5. Matrix Generation & Flake Architecture

The repository dynamically maps package definitions across the matrix:

```nix
{
  outputs = { self, nixpkgs }:
    bionicLib.eachSystem bionicLib.supportedSystems (system: {
      # Flat packages per host system: packages.${system}.${targetName}-${pkgName}
      # Explicit CLI:  nix build .#${targetName}-${packageName}
      packages = { ... };

      # Hierarchical package matrix: legacyPackages.${system}.${targetName}.${packageName}
      # Explicit CLI:  nix build .#${targetName}.${packageName}
      # Full CLI:      nix build .#legacyPackages.${system}.${targetName}.${packageName}
      legacyPackages = { ... };

      # ADB Push helpers (pushes binaries + runtime library closures):
      # Explicit CLI:  nix run .#push-${targetName}-${packageName}
      apps = { ... };

      # Development Shells configured with cross compilers and ADB tools:
      # CLI: nix develop
      devShells = { ... };
    });
}
```

---

## 6. ADB Push & Execution Integration

To make testing binaries on Android hardware or emulators frictionless, every executable package derivation generates corresponding **Nix Apps**: `.#push-${target}-${pkg}`.

### Android Execution Environment & Permissions
- **Staging Directory (`/data/local/tmp/bionic-pkgs/<pkg>/`)**:
  - Android mounts internal storage `/data/local/tmp` with `exec` permissions accessible to the unprivileged `shell` user (UID 2000) over ADB.
  - External storage (`/sdcard`, `/storage/emulated/0`) is mounted with `noexec` and will reject binary execution with `Permission denied`.
  - System partitions (`/system`, `/vendor`) are read-only and require root remounting.
- **Dependency Closure Synchronization**:
  1. **Runtime Closure Query**: The push app queries the package's runtime closure (`nix-store -qR` or Flake closure export).
  2. **Library Synchronization**: Shared libraries are staged to `/data/local/tmp/bionic-pkgs/<pkg>/lib/`.
  3. **Binary Staging**: Pushes the main binary to `/data/local/tmp/bionic-pkgs/<pkg>/bin/` and guarantees executable permissions (`chmod 755`).
  4. **Hardened Relative `$ORIGIN` Runpaths & Hermetic Environment Execution**:
     - Android's dynamic linker does not recognize host `/nix/store/...` paths.
     - Derivations configure `DT_RUNPATH` strictly with `$ORIGIN/../lib` to eliminate search path escaping and prevent library hijacking vulnerabilities (CWE-426/CWE-427). Nested Python C-extension modules scope `$ORIGIN/../..` exclusively via `MODULE_LDFLAGS_SHARED` to resolve libraries inside `prefix/lib`.
     - All packages, launcher scripts, and test runners rely strictly on embedded relative `DT_RUNPATH` without ambient `LD_LIBRARY_PATH`.
  5. **Direct ADB Execution**: Optionally executes the binary interactively via `adb shell`.

---

## 7. Modular On-Device Testing & Parallel CI Matrix

`bionic-pkgs` includes an open, extensible on-device test framework designed to verify all ported CLI utilities and diagnostic tools on target Android devices or emulators.

### Common Test Framework & Helpers (`tests/lib/`)
- `tests/lib/common.sh`: Assertion functions (`assert_ok`, `assert_contains`, `assert_match`, `assert_exit_code`), test counter tracking (`TESTS_RUN`, `TESTS_PASSED`, `TESTS_FAILED`, `TESTS_SKIPPED`), ANSI colorized indicators (`PASS`/`FAIL`/`SKIP`), and summary reporting.
- `tests/lib/adb-helpers.sh`: ADB invocation wrapper supporting `--serial`/`$ANDROID_SERIAL`, device readiness and `adb root` elevation, `tracefs`/`debugfs` mount helpers, and device architecture detection (`adb_get_arch`).

### Codified Tool Test Scripts (`tests/tools/`)
Every testable CLI package implements a dedicated test script under `tests/tools/test-<tool>.sh` accepting `--bin <path_or_launcher>`. Initial tool test scripts include:
- **`strace`**: Version check, write syscall tracing, child process following (`-f`), openat/write file I/O tracing.
- **`python3`**: Stdlib and platform inspection, built-in HACL* SHA-256/MD5 hashes, dynamic C-extensions (`_ctypes`, `_lzma`, `_bz2`), Bionic `libc.so` foreign function calls via `ctypes` (`getpid`, `time`), and compression round-trip.
- **`radare2`**: Version check, `rasm2` instruction assembly/disassembly, `rabin2` binary format inspection, headless analysis (`aaa; afl`), and function disassembly (`s entry0; pdf`).
- **`rizin`**: Version check, architecture-aware `rz-asm` assembly, `rz-bin` format inspection, headless analysis (`aa; afl`), entrypoint disassembly (`pdf`), and `rz-hash` SHA-256 inspection.
- **`elfutils`**: Header inspection (`eu-readelf -h`), section headers (`-S`), dynamic entries/runpaths (`-d`), dynamic symbol extraction (`eu-nm -D`), and segment sizes (`eu-size`).
- **`bpftrace`**: Version check, environment info (`--info`), syscount help, userspace BPF probes, and kernel tracepoint probes with graceful `SKIP` if kernel tracepoints/tracefs are unavailable. Supports both static (`bpftrace-static`) and dynamic sysroot installations.
- **`bcc`**: Introspection utility (`bps`), Python `bcc` module import/version check, standalone tool help (`execsnoop -h`), and BPF C program compilation/execution (`bcc.BPF`) with graceful `SKIP` on missing kernel BPF features.
- **`lldb`**: Version check for `lldb` CLI and companion `lldb-server`, batch execution/process tracing (`--batch`), target image inspection (`target create` / `image list`), breakpoint setting (`breakpoint set -n main`), and control flow.

### Integration Suite & Master Orchestrator (`tests/`)
- `tests/test-integration.sh`: Cross-tool cohabitation integration test verifying `strace` tracing `python3`, `python3` executing BPF programs with `bcc`, `bpftrace` tracing syscalls, `eu-readelf` validating sysroot binaries, and `radare2`/`rizin` disassembling sysroot binaries.
- `tests/run-device-tests.sh`: Master test orchestrator supporting `--tools <list|all>`, `--deploy-mode <push|sysroot>`, `--sysroot-dir <path>`, and `--serial <id>`.

---

## 8. CI/CD & Binary Caching Strategy

### 2-Tier Testing Architecture

- **Tier 1: Fast Smoke / Device Verification** (`.github/workflows/fast-smoke.yml` & `scripts/ci-fast-smoke-test.sh`):
  - Provides rapid canary verification (<3 minutes) by testing the core toolchain triad: `strace`, `elfutils`, and `python3` (covering Bionic syscalls/ptrace, multi-.so ELF/DWARF libraries, and dynamic C-extensions/FFI).
  - Executes target static ELF checks (`check-elf-x86_64-android-*`).
  - Boots a single Android API 34 x86_64 emulator instance (`ubuntu-22.04` with KVM), deploys all three packages, and invokes the test orchestrator (`tests/run-device-tests.sh --tools strace,elfutils,python3`).

- **Tier 2: Full Matrix Build & Sysroot Integration** (`.github/workflows/ci.yml` & `scripts/ci-emulator-test.sh`):
  - Executes full matrix builds across host platforms and Android target ABIs (`aarch64-android`, `x86_64-android`).
  - Unpacks `sysroot-x86_64.tar.gz` and `bpftrace-static-x86_64.tar.gz` on an Android API 34 emulator instance to run standalone static `bpftrace`, master sysroot orchestrator (`run-device-tests.sh --deploy-mode sysroot`), and cross-tool integration suite (`test-integration.sh`).

### Audit & Toolchain Inspection Workflow

- **Audit / Toolchain Flags & Dependencies** (`.github/workflows/audit.yml`):
  - Unified audit workflow running across host systems (`x86_64-linux`, `aarch64-darwin`) and target ABIs (`aarch64-android`, `x86_64-android`).
  - Inspects and verifies toolchain flags (`verify-flags`) and generates project dependency graphs (`scripts/list-deps.sh`).

### Phased Binary Caching
- **Design for Cacheability**: The architecture guarantees deterministic store paths and pure derivations, ensuring out-of-the-box compatibility with any Nix binary cache.
- **Cachix Setup**: Cachix substituter configuration (`bionic-pkgs.cachix.org`) is actively integrated via `nixConfig` in `flake.nix`. GitHub CI is securely configured to push artifacts to this cache on successful matrix builds.

---

## 9. Deterministic Archive & Runtime Bundle Architecture

`bionic-pkgs` uses a modular, 3-layer architecture for building reproducible runtime archives and deployment sysroots:

1. **Layer 1: Low-Level Deterministic Tar Builder (`make-archive`)**
   - **Location**: `pkgs/build-support/make-archive/default.nix`
   - **Role**: Takes an existing directory or derivation output and packs it into a bit-for-bit reproducible archive (`.tar.gz`, `.tar.zst`, or `.tar`).
   - **Determinism Flags**: Enforces owner/group (`--owner=0 --group=0`), numeric ownership (`--numeric-owner`), deterministic modification timestamp (`--mtime='@1'`), and lexicographical file ordering (`--sort=name`).

2. **Layer 2: Factored Staging Script (`scripts/stage-runtime.sh`)**
   - **Location**: `scripts/stage-runtime.sh`
   - **Role**: Accepts a target staging directory and package store paths to aggregate binaries (`bin/`), shared libraries (`lib/`), and share assets (`share/`).
   - **Pruning & Cleaning**: Strips non-runtime build artifacts (`*.a`, `*.la`, `*.o`, `pkgconfig/`, `cmake/`, `doc`, `man`, `info`, `locale`).
   - **Fixups & Launchers**: Optionally calls `scripts/generate-launcher.sh` to create entrypoint wrappers (e.g., `python-launcher.sh`).

3. **Layer 3: High-Level Runtime Bundle Builder (`runtime-archive`)**
   - **Location**: `pkgs/build-support/runtime-archive/default.nix`
   - **Role**: Computes package closures (`lib.closePropagation`), filters out build-time libc/platform stubs (`bionic`), stages runtime outputs via `scripts/stage-runtime.sh`, and emits a deterministic tarball via `make-archive`.
