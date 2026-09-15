# bionic-pkgs ⚡

**Nix Flake for Cross-Compiling Android (Bionic) Tools & Libraries**

`bionic-pkgs` is a nix-native, multi-host, reproducible cross-compilation workspace for Android CLI utilities, debugging tools, profilers, and native libraries targeting Android's Bionic libc.

Built using **Nix Flakes**, it enables seamless cross-compilation across host environments—including ARM64 Linux, ARM64 macOS (Apple Silicon), and x86_64 Linux—targeting Android 14+ (API 34+).

---

## 🌟 Key Features

- **Multi-Host Building**: Build Android tools from any modern developer workstation:
  - `aarch64-linux` (Linux ARM64 / AWS Graviton / Asahi / Raspberry Pi)
  - `aarch64-darwin` (Apple Silicon macOS)
  - `x86_64-linux`
- **Multi-Target Android ABIs**: Cross-compiles for all 4 standard Android target architectures (Android 14+, API 34+):
  - `aarch64-android` (`arm64-v8a` / `aarch64-linux-android` — Primary)
  - `x86_64-android` (`x86_64` / `x86_64-linux-android`)
  - `armv7a-android` (`armeabi-v7a` / `armv7a-linux-androideabi`)
  - `i686-android` (`x86` / `i686-linux-android`)
- **Hermetic & Reproducible**: Fully declared, reproducible dependency graph managed by Nix. Eliminates imperative SDK/NDK setups, host path pollution, and brittle ad-hoc prebuilts.
- **Low-Level Diagnostics & Reversing Catalog**: Focused on deep system debugging, dynamic tracing, and reverse engineering: BPF tools (`bpftrace`, `bcc`), debuggers & tracers (`strace`, `gdb`, `lldb`), reverse engineering suites (`radare2`, `rizin`), portable runtimes (`python3` with `ctypes`), and essential CLI utilities.

---

## 🏗 System Architecture

For detailed architectural specifications, toolchain strategy, and Bionic porting patterns, see our documentation suite:

| Document | Description |
| :--- | :--- |
| 📘 [**Architecture Overview**](docs/architecture.md) | Cross-toolchain strategy, Nixpkgs integration, caching & Flake schemas. |
| 🚀 [**Roadmap**](docs/roadmap.md) | Phased rollout of packages, features, and platform capabilities. |
| 🛠 [**Bionic Porting Guide**](docs/bionic-porting-guide.md) | Deep dive into Bionic libc quirks, shims, PIE requirements, and patch patterns. |
| 🤖 [**Agent Guidelines**](.agents/AGENTS.md) | Guidelines and rules for AI agents and contributors working on this repository. |

---

## 🚀 Quickstart (Preview)

> *Note: `bionic-pkgs` is currently in early active setup. Flake schema details are finalized in [docs/architecture.md](docs/architecture.md).*

### Precompiled Standalone Installation (Non-Nix Users)

Precompiled binary bundles for Android devices are published automatically on every main branch update and tag release:
- 📦 **[Download Precompiled Bundles from GitHub Releases (Latest)](https://github.com/michalgr/bionic-pkgs/releases/tag/latest)**

Follow these step-by-step instructions to push, extract, and execute tools on your Android device via ADB:

```bash
# 1. Download sysroot-<arch>.tar.gz from GitHub Releases (latest)
# 2. Push to Android device
adb push sysroot-aarch64.tar.gz /data/local/tmp/

# 3. Extract to /data/local/tmp/sysroot
adb shell "mkdir -p /data/local/tmp/sysroot && tar -xzf /data/local/tmp/sysroot-aarch64.tar.gz -C /data/local/tmp/sysroot"

# 4. Run tools via the environment launcher wrapper
adb shell "/data/local/tmp/sysroot/env.sh tmux"
adb shell "/data/local/tmp/sysroot/env.sh nmap -sn 127.0.0.1"
adb shell "/data/local/tmp/sysroot/env.sh strace -p 1"
```

---

### Binary Cache (Cachix) & Nix Usage

`bionic-pkgs` maintains a Cachix binary cache containing prebuilt binaries for Linux (`x86_64-linux`) and macOS (`aarch64-darwin`).

To configure the Cachix substituter on your system:

```bash
cachix use bionic-pkgs
```

You can run tools directly from the Flake without building from source:

```bash
# Push and run tmux directly to a connected Android device:
nix run github:michalgr/bionic-pkgs#push-aarch64-android-tmux
```

### Building a package for Android ARM64

```bash
# Build strace for arm64-v8a from any supported host (explicit target syntax):
nix build .#aarch64-android.strace
nix build .#aarch64-android-strace

# Or specify explicit host system and target ABI output:
nix build .#legacyPackages.x86_64-linux.aarch64-android.strace
nix build .#legacyPackages.aarch64-darwin.aarch64-android.strace
```

### Direct Push & Run via ADB

```bash
# Cross-compile strace and push directly to connected Android device via ADB:
nix run .#push-aarch64-android-strace

# Or specify explicit host system:
nix run .#apps.x86_64-linux.push-aarch64-android-strace
```

---

## 📦 Tool Catalog Table

`bionic-pkgs` provides a comprehensive suite of precompiled, 16 KB page-aligned utilities for Android system analysis:

| Category | Available Tools |
| :--- | :--- |
| **Diagnostics** | `strace`, `gdb`, `lldb`, `tcpdump`, `iperf3`, `lsof`, `nmap` (`ncat`, `nping`) |
| **Tracing & Kernel** | `libbpf`, `bcc`, `bpftrace` |
| **Reversing** | `radare2`, `rizin`, `elfutils` |
| **Core & Runtimes** | `python3`, `tmux`, `curl`, `socat`, `htop` |

---

## 🤝 Contributing

Contributions are welcome! Please check out [docs/bionic-porting-guide.md](docs/bionic-porting-guide.md) for guidelines on packaging new utilities and fixing Bionic libc cross-compilation errors.

---

## 📜 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
