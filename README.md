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

### Binary Cache (Cachix)

`bionic-pkgs` uses a Cachix binary cache to speed up builds. By default, the `flake.nix` is configured to use the `bionic-pkgs` cache. When you run your first `nix build` or `nix run` command, Nix will ask if you want to trust the cache settings provided by the flake. We recommend saying `y` to avoid having to compile packages from source.

### Building a package for Android ARM64

```bash
# Build strace for arm64-v8a from any supported host (auto-resolves host platform)
nix build .#strace
nix build .#aarch64-android.strace

# Or specify explicit host system and target ABI output:
nix build .#legacyPackages.x86_64-linux.aarch64-android.strace
nix build .#legacyPackages.aarch64-darwin.aarch64-android.strace
```

### Direct Push & Run via ADB

```bash
# Cross-compile strace and push directly to connected Android device via ADB
nix run .#push-strace
nix run .#push-aarch64-android-strace

# Or specify explicit host system:
nix run .#apps.x86_64-linux.push-aarch64-android-strace
```

### Automated Flake Checks & Dependency Auditing

```bash
# Run automated ELF property verifications and package dependency reports across all targets:
nix flake check --print-build-logs
```

---

## 🤝 Contributing

Contributions are welcome! Please check out [docs/bionic-porting-guide.md](docs/bionic-porting-guide.md) for guidelines on packaging new utilities and fixing Bionic libc cross-compilation errors.

---

## 📜 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
