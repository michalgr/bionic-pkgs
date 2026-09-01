#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-aarch64-android}"
SYSTEM="${2:-x86_64-linux}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Evaluating top-level derivations for target '${TARGET}' on system '${SYSTEM}'..."

TOP_DRVS_JSON=$(nix eval --json ".#legacyPackages.${SYSTEM}.${TARGET}" --apply '
  pkgs: builtins.filter (x: x != null) (
    builtins.attrValues (
      builtins.mapAttrs (n: v:
        let
          isDrv = builtins.isAttrs v && (v ? drvPath);
          evalDrv = builtins.tryEval (if isDrv then v.drvPath else null);
        in
        if evalDrv.success then evalDrv.value else null
      ) pkgs
    )
  )
')

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TOP_DRVS_FILE="${TMP_DIR}/top_drvs.txt"
python3 -c '
import json, sys
data = json.loads(sys.argv[1])
for path in data:
    if path:
        print(path)
' "${TOP_DRVS_JSON}" > "${TOP_DRVS_FILE}"

echo "Finding recursive derivation closures..."
ALL_DRVS_FILE="${TMP_DIR}/all_drvs.txt"
xargs nix-store -qR < "${TOP_DRVS_FILE}" | sort -u > "${ALL_DRVS_FILE}"

echo "Categorizing and listing projects..."
python3 "${SCRIPT_DIR}/list-deps.py" --target "${TARGET}" --system "${SYSTEM}" --drv-list-file "${ALL_DRVS_FILE}"
