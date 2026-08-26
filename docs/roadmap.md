# Project Roadmap

This document outlines the phased development roadmap for `bionic-pkgs`.

---

## 🎯 Phase 1: Core Infrastructure & Flake Matrix (Completed)
- [x] Initial architectural design & document suite.
- [x] Implement `flake.nix` with multi-target (`aarch64-android`, `x86_64-android`) matrix generators across standard hosts (`aarch64-linux`, `x86_64-linux`, `aarch64-darwin`).
- [x] Setup Nixpkgs cross-compilation baseline wrappers and Bionic shim overlay (`lib/bionic-compat.nix`).
- [x] Implement ADB deployment helpers (`nix run .#push-<pkg>`) with staging directory creation and launcher scripts.
- [x] Configure GitHub Actions workflow for CI matrix building.

---

## 🛠 Phase 2: Initial Core Tooling (Diagnostics, Reversing & Python)
Port, patch, and verify initial priority packages for `aarch64-android` (`arm64-v8a`) and `x86_64-android`:
- [x] **`pkgs/diagnostics/` (System Diagnostics & Tracing)**:
  - [x] `pkgs/diagnostics/strace`: Full syscall decoding, MPERS support, and verified live on Android 14+ devices.
- [x] **`pkgs/runtime/` & `pkgs/libs/` (Python 3 Runtime & Shared Libraries)**:
  - [x] `pkgs/runtime/python3`: Standalone minimal CLI runtime for Android.
  - [x] `pkgs/libs/libffi`: Cross-compiled for Bionic to support Python `ctypes` (essential for dynamic C library interaction and memory inspection without APK wrappers).
  - [x] `pkgs/libs/android-prebuilts`: Official Google Android NDK platform headers (`log.h`, `trace.h`, `zlib.h`, `jni.h`) and platform library stubs (`libz.so`, `liblog.so`, `libandroid.so`, etc.).
  - [x] `pkgs/libs/xz`: Cross-compiled XZ Utils compression library (`liblzma`) and CLI tools (`xz`, `unxz`, `xzcat`, `lzma`) for Android.
  - [x] `pkgs/libs/zstd`: Cross-compiled Zstandard compression library (`libzstd`) and CLI tools (`zstd`, `unzstd`, `zstdcat`, `zstdmt`) for Android.
  - [ ] Supporting optional libraries: `pkgs/libs/readline`, `pkgs/libs/openssl`, `pkgs/libs/ncurses`.
  - [x] `pkgs/libs/elfutils`: Minimalistic ELF manipulation (`libelf`, `eu-readelf`, `eu-nm`, `eu-strip`, etc.) and DWARF debugging (`libdw`, `libasm`) suite.
- [x] **`pkgs/reversing/` (Disassembly & Binary Analysis)**:
  - [x] `pkgs/reversing/radare2`: Standalone binary analysis framework.
  - [x] `pkgs/reversing/rizin`: Reverse engineering framework and command-line disassembler.
- [ ] **`pkgs/core/` (Core Unix CLI Utilities)**:
  - `pkgs/core/htop`, `pkgs/core/curl`, `pkgs/core/socat`.

---

## 🔬 Phase 3: eBPF Tracing & Advanced Debuggers
- [ ] **`pkgs/tracing/` & Kernel Diagnostics**:
  - [x] `pkgs/tracing/bcc`: BPF Compiler Collection.
  - [ ] `pkgs/tracing/bpftrace`: High-level kernel dynamic tracing language and runtime.
  - [x] `pkgs/tracing/libbpf`: Core BPF object loader library.
- [ ] **`pkgs/diagnostics/` (Debuggers)**:
  - `pkgs/diagnostics/gdb`: GDB & `gdbserver` cross-compiled for Bionic.
  - `pkgs/diagnostics/lldb`: LLVM native target debugger.

---

## ⚡ Phase 4: Extended Tools & Legacy 32-bit ABI Support
- [ ] Legacy 32-bit Android ABI support (`armv7a-android`, `i686-android`) via custom Bionic sysroot bootstrap.
- [ ] Port additional diagnostic & networking utilities:
  - `pkgs/diagnostics/tcpdump`
  - `pkgs/diagnostics/lsof`
  - `pkgs/diagnostics/nmap`
  - `pkgs/diagnostics/iperf3`

---

## 🤖 Phase 5: Developer Experience, ADB Automation & Caching
- [x] Implement `nix run .#push-<pkg>` (and `.#push-<target>-<pkg>`) ADB push helpers with runtime dependency closure synchronization and launcher wrapper.
- [x] `devShells` featuring cross-compilers, ADB binaries, and environment variables.
- [ ] Automated integration test suite running on Android emulators in CI.
- [ ] Enable Cachix binary cache substituters for prebuilt package distribution.
