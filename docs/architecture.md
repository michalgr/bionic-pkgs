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
Host outputs are generated dynamically via `flake-utils.lib.eachSystem bionicLib.supportedSystems`:
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

Packages are organized in `pkgs/` by functional category:

```
bionic-pkgs/
├── flake.nix
├── lib/
│   ├── default.nix
│   └── bionic-compat.nix
├── pkgs/
│   ├── default.nix
│   ├── diagnostics/     # Debuggers, syscall monitors, crash dump tools (strace, gdb, lldb)
│   ├── tracing/         # eBPF tools, kernel probes, performance analyzers (bcc, bpftrace)
│   ├── reversing/       # Disassemblers, binary analysis tools (radare2, rizin)
│   ├── runtime/         # Interpreters, language engines (python3)
│   ├── core/            # Core system utilities (tree, file, tmux, bash)
│   └── libs/            # Shared libraries, polyfills (bionic-compat, libffi, elfutils, libbpf)
```

---

## 5. Matrix Generation & Flake Architecture

The repository dynamically maps package definitions across the matrix:

```nix
{
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem bionicLib.supportedSystems (system: {
      # Flat packages per host system: packages.${system}.${pkgName} and packages.${system}.${targetName}-${pkgName}
      # Shorthand CLI: nix build .#${packageName}
      # Explicit CLI:  nix build .#${targetName}-${packageName}
      packages = { ... };

      # Hierarchical package matrix: legacyPackages.${system}.${targetName}.${packageName}
      # Shorthand CLI: nix build .#${targetName}.${packageName}
      # Explicit CLI:  nix build .#legacyPackages.${system}.${targetName}.${packageName}
      legacyPackages = { ... };

      # ADB Push helpers (pushes binaries + runtime library closures):
      # Shorthand CLI: nix run .#push-${packageName}
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

To make testing binaries on Android hardware or emulators frictionless, every executable package derivation generates corresponding **Nix Apps**: `.#push-${pkg}` (for default `aarch64-android`) and `.#push-${target}-${pkg}`.

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

### Package Dependency Verification & Reporting
- **Automated Dependency Auditing**: For every package evaluated in `bionic-pkgs` (e.g., `strace`, `bcc`, `radare2`, `python3`), `nix flake check` automatically executes a dependency reporting check (`check-deps-${targetName}-${pkgName}`).
- **Store Path & Closure Inspection**: Utilizing `exportReferencesGraph`, each verification check extracts direct build/runtime dependencies, identifies Bionic ecosystem packages in the closure, and reports the complete transitive store path closure.
- **Aggregate Matrix Summary**: An aggregate check `check-deps-summary` combines all package dependency reports across target architectures into a single unified matrix report (`$out/summary.txt`).

### Phased Binary Caching
- **Design for Cacheability**: The architecture guarantees deterministic store paths and pure derivations, ensuring out-of-the-box compatibility with any Nix binary cache.
- **Cachix Setup**: Cachix substituter configuration (`bionic-pkgs.cachix.org`) is actively integrated via `nixConfig` in `flake.nix`. GitHub CI is securely configured to push artifacts to this cache on successful matrix builds.
