# Project Roadmap

This document outlines the phased development roadmap for `bionic-pkgs`.

---

## 🎯 Phase 1: Core Infrastructure & Flake Matrix (Current)
- [x] Initial architectural design & document suite.
- [ ] Implement `flake.nix` using `flake-utils.lib.eachDefaultSystem` and multi-target (`aarch64-android`, `x86_64-android`, `armv7a-android`, `i686-android`) matrix generators.
- [ ] Setup Nixpkgs cross-compilation baseline wrappers and Bionic shim overlay (`lib/bionic-compat.nix`).
- [ ] Configure GitHub Actions workflow for CI matrix building.

---

## 🛠 Phase 2: Initial Core Tooling (Diagnostics, Reversing & Python)
Port, patch, and verify initial priority packages for `aarch64-android` (`arm64-v8a`):
- [ ] **`pkgs/runtime/` & `pkgs/libs/` (Python 3 Runtime & Shared Libraries)**:
  - `pkgs/runtime/python3`: Standalone CLI runtime for Android.
  - `pkgs/libs/libffi`: Cross-compiled for Bionic to support Python `ctypes` (essential for dynamic C library interaction and memory inspection without APK wrappers).
  - Supporting libraries: `pkgs/libs/zlib`, `pkgs/libs/readline`, `pkgs/libs/openssl`, `pkgs/libs/ncurses`.
- [ ] **`pkgs/diagnostics/` (System Diagnostics & Tracing)**:
  - `pkgs/diagnostics/strace`: Full syscall decoding and signal inspection on Android kernels.
- [ ] **`pkgs/reversing/` (Disassembly & Binary Analysis)**:
  - `pkgs/reversing/radare2`: Standalone binary analysis framework.
  - `pkgs/reversing/rizin`: Reverse engineering suite and command-line disassembler.
- [ ] **`pkgs/core/` (Core Unix CLI Utilities)**:
  - `pkgs/core/htop`, `pkgs/core/zstd`, `pkgs/core/curl`, `pkgs/core/socat`.

---

## 🔬 Phase 3: eBPF Tracing & Advanced Debuggers
- [ ] **`pkgs/tracing/` & Kernel Diagnostics**:
  - `pkgs/tracing/bcc`: BPF Compiler Collection.
  - `pkgs/tracing/bpftrace`: High-level kernel dynamic tracing language and runtime.
  - `pkgs/tracing/libbpf` & `pkgs/libs/elfutils`: Core BPF object loader and ELF inspection libraries.
- [ ] **`pkgs/diagnostics/` (Debuggers)**:
  - `pkgs/diagnostics/gdb`: GDB & `gdbserver` cross-compiled for Bionic.
  - `pkgs/diagnostics/lldb`: LLVM native target debugger.

---

## ⚡ Phase 4: Multi-Target ABI Expansion & Extended Tools
- [ ] Extend package matrix compilation to all target ABIs: `x86_64-android`, `armv7a-android`, `i686-android`.
- [ ] Port additional diagnostic & networking utilities:
  - `pkgs/diagnostics/tcpdump`
  - `pkgs/diagnostics/lsof`
  - `pkgs/diagnostics/nmap`
  - `pkgs/diagnostics/iperf3`

---

## 🤖 Phase 5: Developer Experience, ADB Automation & Caching
- [ ] Implement `nix run .#<target>.<pkg>.push` (and `.#apps.<system>.<target>.<pkg>.push`) ADB push helpers with runtime dependency closure synchronization.
- [ ] `devShells` featuring cross-compilers, ADB binaries, and environment variables.
- [ ] Automated integration test suite running on Android emulators in CI.
- [ ] Enable Cachix binary cache substituters for prebuilt package distribution.
