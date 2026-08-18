# Agent Guidelines for bionic-pkgs

Welcome AI Agent! You are working on `bionic-pkgs`, a Nix Flake project designed to cross-compile CLI tools, debugging suites, and libraries for Android 14+ (Bionic libc) targets across standard host architectures (`aarch64-linux`, `aarch64-darwin`, `x86_64-linux`).

---

## 🏗 Repository Structure & Code Style

- `flake.nix`: Main Flake entrypoint exposing matrix packages, devShells, apps, and checks.
- `lib/`: Nix library helpers for generating matrix outputs and Bionic stdenv compatibility overlays.
- `pkgs/`: Package derivations grouped logically (`pkgs/diagnostics/`, `pkgs/tracing/`, `pkgs/reversing/`, `pkgs/runtime/`, `pkgs/core/`, `pkgs/libs/`).
- `docs/`: System documentation (`architecture.md`, `roadmap.md`, `bionic-porting-guide.md`).

### Nix Code Formatting Guidelines
- Use standard 2-space indentation for `.nix` files.
- Ensure all derivations use standard `meta` fields (`description`, `homepage`, `license`, `platforms`, `maintainers`).
- When patching upstream packages for Bionic, include brief in-code comments in the derivation and provide an in-depth treatment in `docs/bionic-porting-guide.md`.

---

## 🧪 Verification Protocol

Before declaring any package complete or bug fixed:
1. Cross-compile the target package derivation using Nix:
   ```bash
   # Inferred host (evaluates legacyPackages.${system}.<target>.<pkg>):
   nix build .#<target>.<pkg>

   # Or explicit host and target:
   nix build .#legacyPackages.<host>.<target>.<pkg>
   ```
2. Verify ELF file properties using `file` and `llvm-readelf`:
   - **ELF Architecture**: `ARM aarch64`, `ARM` (32-bit), `x86-64`, or `Intel 80386`.
   - **Dynamic Linker**: `/system/bin/linker64` (64-bit targets: `aarch64`, `x86_64`) or `/system/bin/linker` (32-bit targets: `armv7a`, `i686`).
   - **16 KB Memory Page Alignment**: Run `llvm-readelf -l <binary> | grep -E 'LOAD|Align'` and ensure all `LOAD` segments satisfy `Align >= 0x4000` (16384).
   - **Dynamic Dependencies & Runpaths**: Run `llvm-readelf -d <binary>` and verify:
     - Needed libraries link against Bionic (`libc.so`, `libm.so`, `libdl.so`) or staged packages.
     - glibc-specific libraries (`libpthread.so`, `librt.so`, `libutil.so`, `libresolv.so`, `libcrypt.so`) are **NOT** present.
     - `DT_RUNPATH` uses relative origin paths (e.g. `$ORIGIN/../lib:$ORIGIN/lib`) rather than host `/nix/store/...` paths.
3. Test push functionality and verify execution on an Android device or emulator via ADB in `/data/local/tmp/`.
