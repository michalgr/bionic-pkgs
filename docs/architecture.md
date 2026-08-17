# System Architecture Specification

## 1. Vision & Core Philosophy

`bionic-pkgs` is designed to be the definitive, reproducible package collection and cross-compilation matrix for Android (Bionic libc) target binaries.

### Why standard Android NDK is insufficient
Cross-compiling standalone Linux CLI tools and diagnostic utilities for Android with the standard Google NDK is notoriously painful:
1. **Transitive dependencies are hard**: Manually building and linking non-trivial dependency chains (e.g. `libffi`, `readline`, `ncurses`, `openssl`) without a package manager is brittle and time-consuming.
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
Host outputs are generated dynamically via `flake-utils.lib.eachDefaultSystem`:
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
- **No `ndk-build` Needed**: Standard Unix build systems (Autotools, CMake, Meson, Makefiles) build directly through Nix cross-stdenv. We do not use `ndk-build` or legacy Android build scripts.
- **Android Platform Libraries**: When packages require Android-specific logging or system stubs (e.g. `liblog`, `android/log.h`), they link directly against the hermetic sysroot libraries provided by the cross-stdenv.

---

## 4. Package Organization & Taxonomy

Packages are organized in `pkgs/` by functional category:

```
bionic-pkgs/
├── flake.nix
├── flake.lock
├── README.md
├── docs/
│   ├── architecture.md
│   ├── roadmap.md
│   └── bionic-porting-guide.md
├── .agents/
│   └── AGENTS.md
├── lib/
│   ├── default.nix            # Flake utility functions & matrix generators
│   └── bionic-compat.nix       # Bionic patch sets, CFLAGS, and shim hooks
└── pkgs/
    ├── diagnostics/           # Deep debugging & system tracers
    │   ├── strace/
    │   ├── gdb/
    │   └── lldb/
    ├── tracing/               # BPF and dynamic kernel tracing
    │   ├── bpftrace/
    │   ├── bcc/
    │   └── libbpf/
    ├── reversing/             # Reverse engineering & binary analysis
    │   ├── radare2/
    │   └── rizin/
    ├── runtime/               # Portable language runtimes
    │   └── python3/           # Python 3 with ctypes (libffi) support
    ├── core/                  # Core Unix CLI utilities
    │   ├── htop/
    │   ├── zstd/
    │   ├── curl/
    │   └── socat/
    └── libs/                  # Shared library dependencies
        ├── libffi/
        ├── ncurses/
        ├── readline/
        ├── openssl/
        ├── elfutils/
        └── zlib/
```

---

## 5. Nix Flake Schema & Output Structure

Outputs are generated using `flake-utils.lib.eachDefaultSystem`, producing target cross-compilation matrix packages, dev shells, and ADB apps per host:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      # Target matrix packages per host system: packages.${system}.${targetKey}.${packageName}
      # Shorthand CLI: nix build .#${targetKey}.${packageName}
      # Explicit CLI:  nix build .#packages.${system}.${targetKey}.${packageName}
      packages = { ... };

      # Development Shells configured with cross compilers and ADB tools:
      # CLI: nix develop .#${targetKey}
      devShells = { ... };

      # ADB Push helpers (pushes binaries + runtime library closures):
      # Shorthand CLI: nix run .#${targetKey}.${packageName}.push
      # Explicit CLI:  nix run .#apps.${system}.${targetKey}.${packageName}.push
      apps = { ... };
    });
}
```

---

## 6. ADB Push & Execution Integration

To make testing binaries on Android hardware or emulators frictionless, every executable package derivation generates a corresponding **Nix App**: `.#${target}.${pkg}.push`.

### Android Execution Environment & Permissions
- **Staging Directory (`/data/local/tmp/bionic-pkgs/<pkg>/`)**:
  - Android mounts internal storage `/data/local/tmp` with `exec` permissions accessible to the unprivileged `shell` user (UID 2000) over ADB.
  - External storage (`/sdcard`, `/storage/emulated/0`) is mounted with `noexec` and will reject binary execution with `Permission denied`.
  - System partitions (`/system`, `/vendor`) are read-only and require root remounting.
- **Dependency Closure Synchronization**:
  1. **Runtime Closure Query**: The push app queries the package's runtime closure (`nix-store -qR` or Flake closure export).
  2. **Library Synchronization**: Shared libraries are staged to `/data/local/tmp/bionic-pkgs/<pkg>/lib/`.
  3. **Binary Staging**: Pushes the main binary to `/data/local/tmp/bionic-pkgs/<pkg>/bin/` and guarantees executable permissions (`chmod 755`).
  4. **Relative `$ORIGIN` Runpaths & Environment Wrapper**:
     - Android's dynamic linker does not recognize host `/nix/store/...` paths.
     - Derivations configure `DT_RUNPATH` with `$ORIGIN/../lib:$ORIGIN/lib`.
     - The push app generates a wrapper script exporting `LD_LIBRARY_PATH=/data/local/tmp/bionic-pkgs/<pkg>/lib` as a fallback.
  5. **Direct ADB Execution**: Optionally executes the binary interactively via `adb shell`.

---

## 7. CI/CD & Binary Caching Strategy

### GitHub Actions CI
A GitHub Actions workflow (`.github/workflows/ci.yml`) will validate the cross-compilation matrix across host platforms:
- `ubuntu-latest` (`x86_64-linux`)
- `macos-latest` (`aarch64-darwin`)
- ARM64 Linux runner / container (`aarch64-linux`)

### Phased Binary Caching
- **Design for Cacheability**: The architecture guarantees deterministic store paths and pure derivations, ensuring out-of-the-box compatibility with any Nix binary cache.
- **Cachix Setup**: Cachix substituter configuration (`bionic-pkgs.cachix.org`) and signing credentials will be integrated as an enhancement once the package set expands and builds scale up.
