#!/usr/bin/env bash
# paperclip-hotpatch — Restore last backup of patched files
# Repo: https://github.com/dandacompany/paperclip-hotpatch
#
# Usage (one-liner, no install):
#   curl -fsSL https://raw.githubusercontent.com/dandacompany/paperclip-hotpatch/main/revert.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/dandacompany/paperclip-hotpatch/main/revert.sh | bash -s -- <timestamp>
#
# Restores files from ~/.paperclip-patches/<timestamp>/ to their original locations
# and restarts paperclip.service if available.

set -euo pipefail

BAK_ROOT="$HOME/.paperclip-patches"
if [[ ! -d "$BAK_ROOT" ]]; then
  echo "ERROR: no backup dir at $BAK_ROOT" >&2
  exit 1
fi

if [[ $# -ge 1 ]]; then
  BAK="$BAK_ROOT/$1"
else
  BAK="$(ls -dt "$BAK_ROOT"/*/ 2>/dev/null | head -1)"
  BAK="${BAK%/}"
fi

if [[ ! -d "$BAK" ]]; then
  echo "ERROR: backup not found: $BAK" >&2
  echo "Available:" >&2
  ls "$BAK_ROOT" >&2 || true
  exit 1
fi

if [[ ! -f "$BAK/paths.txt" ]]; then
  echo "ERROR: $BAK/paths.txt missing — cannot determine restore targets" >&2
  exit 1
fi

mapfile -t PATHS < "$BAK/paths.txt"
ADAPTER_FILE="${PATHS[0]:-}"
UI_FILE="${PATHS[1]:-}"

if [[ -f "$BAK/adapter-index.js.orig" && -n "$ADAPTER_FILE" ]]; then
  cp "$BAK/adapter-index.js.orig" "$ADAPTER_FILE"
  echo "[restore] $ADAPTER_FILE"
fi

if [[ -f "$BAK/ui-bundle.js.orig" && -n "$UI_FILE" ]]; then
  cp "$BAK/ui-bundle.js.orig" "$UI_FILE"
  echo "[restore] $UI_FILE"
fi

if command -v systemctl >/dev/null 2>&1 \
   && systemctl list-unit-files --no-pager 2>/dev/null | grep -q '^paperclip.service' \
   && sudo -n true 2>/dev/null; then
  sudo systemctl restart paperclip.service
  echo "[restart] paperclip.service"
fi

echo "[done] reverted from $BAK"
