#!/usr/bin/env python3
import json
import sys
import os
import subprocess
import argparse

def parse_args():
    parser = argparse.ArgumentParser(description="Categorize and list recursive build and host machine dependencies.")
    parser.add_argument("--target", required=True, help="Target architecture (e.g. aarch64-android or x86_64-android)")
    parser.add_argument("--system", required=True, help="Host system runner (e.g. x86_64-linux or aarch64-darwin)")
    parser.add_argument("--drv-list-file", help="Path to file containing list of derivation paths (one per line)")
    parser.add_argument("--json-input", help="Path to nix derivation show JSON file (or stdin if omitted)")
    return parser.parse_args()

def clean_name(drv_path, env):
    pname = env.get("pname")
    version = env.get("version")
    if pname and version:
        return f"{pname}-{version}"
    if pname:
        return pname
    name = env.get("name")
    if name:
        return name

    drv_filename = os.path.basename(drv_path)
    if drv_filename.endswith(".drv"):
        drv_filename = drv_filename[:-4]
    if len(drv_filename) > 33 and drv_filename[32] == "-":
        drv_filename = drv_filename[33:]
    return drv_filename

def is_target_dep(drv_path, drv_info, target_triple):
    env = drv_info.get("env", {})
    chost = env.get("CHOST", "")
    cross_config = env.get("crossConfig", "")
    configure_flags = env.get("configureFlags", "")
    cmake_flags = env.get("cmakeFlags", "")
    meson_flags = env.get("mesonFlags", "")
    cargo_target = env.get("CARGO_BUILD_TARGET", "")
    cflags = env.get("NIX_CROSS_CFLAGS_COMPILE", "") or env.get("NIX_CFLAGS_COMPILE", "")

    # Direct match on CHOST or crossConfig target triple
    if target_triple in chost or target_triple in cross_config:
        return True
    if target_triple in cargo_target:
        return True
    if f"--host={target_triple}" in configure_flags:
        return True
    if "android" in cross_config or "android" in chost:
        return True
    if "-DCMAKE_SYSTEM_NAME=Android" in cmake_flags:
        return True

    # Check if derivation explicitly targets android host via cflags or flags
    if "bionic" in cflags.lower() or "android" in cflags.lower():
        return True

    return False

def load_derivations_in_batches(drv_list_file):
    with open(drv_list_file, "r") as f:
        drv_paths = [line.strip() for line in f if line.strip()]

    derivations = {}
    batch_size = 50
    for i in range(0, len(drv_paths), batch_size):
        batch = drv_paths[i:i + batch_size]
        try:
            res = subprocess.run(
                ["nix", "derivation", "show"] + batch,
                capture_output=True,
                text=True,
                check=True
            )
            batch_data = json.loads(res.stdout)
            derivations.update(batch_data)
        except Exception as e:
            sys.stderr.write(f"Warning: Failed to run nix derivation show on batch {i}: {e}\n")
    return derivations

def main():
    args = parse_args()

    target_triples = {
        "aarch64-android": "aarch64-unknown-linux-android",
        "x86_64-android": "x86_64-unknown-linux-android",
    }
    target_triple = target_triples.get(args.target, f"{args.target}-unknown-linux-android")

    if args.drv_list_file and os.path.exists(args.drv_list_file):
        derivations = load_derivations_in_batches(args.drv_list_file)
    elif args.json_input and os.path.exists(args.json_input):
        with open(args.json_input, "r") as f:
            derivations = json.load(f)
    else:
        derivations = json.load(sys.stdin)

    target_deps = {}
    build_deps = {}

    for drv_path, drv_info in derivations.items():
        env = drv_info.get("env", {})
        name = clean_name(drv_path, env)

        if is_target_dep(drv_path, drv_info, target_triple):
            target_deps[name] = drv_path
        else:
            build_deps[name] = drv_path

    print("=" * 80)
    print(f"RECURSIVE DEPENDENCY LIST FOR TARGET: {args.target} ({target_triple})")
    print(f"HOST BUILD RUNNER: {args.system}")
    print("=" * 80)
    print()

    print(f"--- TARGET MACHINE PROJECTS (built for {args.target}) [{len(target_deps)}] ---")
    for name in sorted(target_deps.keys()):
        print(f"  - {name} ({target_deps[name]})")
    print()

    print(f"--- BUILD MACHINE PROJECTS (built for {args.system}) [{len(build_deps)}] ---")
    for name in sorted(build_deps.keys()):
        print(f"  - {name} ({build_deps[name]})")
    print()

    print("=" * 80)
    print(f"SUMMARY: {len(target_deps)} target machine projects, {len(build_deps)} build machine projects.")
    print("=" * 80)

if __name__ == "__main__":
    main()
