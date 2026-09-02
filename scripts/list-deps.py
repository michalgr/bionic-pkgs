#!/usr/bin/env python3
import json
import sys
import os
import subprocess
import argparse

def parse_args():
    parser = argparse.ArgumentParser(description="Categorize and list recursive build and host machine dependencies.")
    parser.add_argument("--target", required=True, help="Target architecture (e.g. aarch64-android, x86_64-android, armv7a-android, i686-android)")
    parser.add_argument("--system", required=True, help="Host system runner (e.g. x86_64-linux or aarch64-darwin)")
    parser.add_argument("--drv-list-file", help="Path to file containing list of derivation paths (one per line)")
    parser.add_argument("--json-input", help="Path to nix derivation show JSON file")
    return parser.parse_args()

def extract_drvs(data):
    if isinstance(data, dict):
        drvs = data.get("derivations", data)
        if isinstance(drvs, dict):
            return {k: v for k, v in drvs.items() if isinstance(v, dict)}
    return {}

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
    env = drv_info.get("env", {}) if isinstance(drv_info, dict) else {}
    chost = env.get("CHOST", "")
    cross_config = env.get("crossConfig", "")
    configure_flags = env.get("configureFlags", "")
    cmake_flags = env.get("cmakeFlags", "")
    meson_flags = env.get("mesonFlags", "")
    cargo_target = env.get("CARGO_BUILD_TARGET", "")
    cflags = env.get("NIX_CROSS_CFLAGS_COMPILE", "") or env.get("NIX_CFLAGS_COMPILE", "")

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

    if "bionic" in cflags.lower() or "android" in cflags.lower():
        return True

    return False

def load_derivations_in_batches(drv_list_file):
    with open(drv_list_file, "r") as f:
        drv_paths = [line.strip() for line in f if line.strip().endswith(".drv")]

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
            raw_data = json.loads(res.stdout)
            batch_data = extract_drvs(raw_data)
            derivations.update(batch_data)
        except Exception:
            for drv_path in batch:
                try:
                    res = subprocess.run(
                        ["nix", "derivation", "show", drv_path],
                        capture_output=True,
                        text=True,
                        check=True
                    )
                    raw_data = json.loads(res.stdout)
                    single_data = extract_drvs(raw_data)
                    derivations.update(single_data)
                except Exception as e:
                    sys.stderr.write(f"Warning: Failed to show derivation {drv_path}: {e}\n")
    return derivations

def print_group(group_name, target_arch, deps_map):
    total_drvs = sum(len(paths) for paths in deps_map.values())
    print(f"--- {group_name} (built for {target_arch}) [{len(deps_map)} projects, {total_drvs} derivations] ---")
    for name in sorted(deps_map.keys()):
        paths = sorted(deps_map[name])
        if len(paths) == 1:
            print(f"  - {name} ({paths[0]})")
        else:
            print(f"  - {name} [{len(paths)} derivations]:")
            for p in paths:
                print(f"      * {p}")
    print()

def main():
    args = parse_args()

    target_triples = {
        "aarch64-android": "aarch64-unknown-linux-android",
        "x86_64-android": "x86_64-unknown-linux-android",
        "armv7a-android": "armv7a-unknown-linux-androideabi",
        "i686-android": "i686-unknown-linux-android",
    }
    target_triple = target_triples.get(args.target, f"{args.target}-unknown-linux-android")

    if args.drv_list_file:
        if not os.path.exists(args.drv_list_file):
            sys.stderr.write(f"Error: Derivation list file not found: {args.drv_list_file}\n")
            sys.exit(1)
        derivations = load_derivations_in_batches(args.drv_list_file)
    elif args.json_input:
        if not os.path.exists(args.json_input):
            sys.stderr.write(f"Error: JSON input file not found: {args.json_input}\n")
            sys.exit(1)
        with open(args.json_input, "r") as f:
            derivations = extract_drvs(json.load(f))
    else:
        derivations = extract_drvs(json.load(sys.stdin))

    if not isinstance(derivations, dict):
        sys.stderr.write("Error: Expected dictionary for derivations\n")
        sys.exit(1)

    target_deps = {}
    build_deps = {}

    for drv_path, drv_info in derivations.items():
        if not isinstance(drv_info, dict):
            continue
        env = drv_info.get("env", {})
        name = clean_name(drv_path, env)
        full_path = drv_path if drv_path.startswith("/") else f"/nix/store/{drv_path}"

        if is_target_dep(drv_path, drv_info, target_triple):
            target_deps.setdefault(name, []).append(full_path)
        else:
            build_deps.setdefault(name, []).append(full_path)

    total_target_drvs = sum(len(p) for p in target_deps.values())
    total_build_drvs = sum(len(p) for p in build_deps.values())

    print("=" * 80)
    print(f"RECURSIVE DEPENDENCY LIST FOR TARGET: {args.target} ({target_triple})")
    print(f"HOST BUILD RUNNER: {args.system}")
    print("=" * 80)
    print()

    print_group("TARGET MACHINE PROJECTS", args.target, target_deps)
    print_group("BUILD MACHINE PROJECTS", args.system, build_deps)

    print("=" * 80)
    print(f"SUMMARY: {len(target_deps)} target machine projects ({total_target_drvs} derivations), {len(build_deps)} build machine projects ({total_build_drvs} derivations).")
    print("=" * 80)

if __name__ == "__main__":
    main()
