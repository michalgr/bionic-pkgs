#!/usr/bin/env bash
set -euo pipefail

CURRENT_SYSTEM=$(nix eval --raw --expr 'builtins.currentSystem' 2>/dev/null || echo "x86_64-linux")
TARGET="${1:-aarch64-android}"
SYSTEM="${2:-${CURRENT_SYSTEM}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Evaluating top-level derivations for target '${TARGET}' on system '${SYSTEM}'..."

TOP_DRVS=$(nix eval --raw ".#legacyPackages.${SYSTEM}.${TARGET}" --apply '
  pkgs: builtins.concatStringsSep "\n" (
    builtins.filter (x: x != "") (
      builtins.attrValues (
        builtins.mapAttrs (n: v:
          let
            isDrv = builtins.isAttrs v && (v ? drvPath);
            evalDrv = builtins.tryEval (if isDrv then v.drvPath else "");
          in
          if evalDrv.success then evalDrv.value else ""
        ) pkgs
      )
    )
  )
')

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TOP_DRVS_FILE="${TMP_DIR}/top_drvs.txt"
printf "%s\n" "${TOP_DRVS}" | grep '\.drv$' > "${TOP_DRVS_FILE}" || true

echo "Finding recursive derivation closures..."
ALL_DRVS_FILE="${TMP_DIR}/all_drvs.txt"
if [ -s "${TOP_DRVS_FILE}" ]; then
  xargs nix-store -qR < "${TOP_DRVS_FILE}" | grep '\.drv$' | sort -u > "${ALL_DRVS_FILE}"
else
  touch "${ALL_DRVS_FILE}"
fi

echo "Categorizing and listing projects..."
python3 "${SCRIPT_DIR}/list-deps.py" --target "${TARGET}" --system "${SYSTEM}" --drv-list-file "${ALL_DRVS_FILE}"
