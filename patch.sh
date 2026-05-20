#!/usr/bin/env bash
# paperclip-hotpatch — Add GPT-5.5 to paperclipai/paperclip codex_local adapter
# Repo: https://github.com/dandacompany/paperclip-hotpatch

set -euo pipefail

REPO_URL="https://github.com/dandacompany/paperclip-hotpatch"
RAW_URL="https://raw.githubusercontent.com/dandacompany/paperclip-hotpatch/main"

show_help() {
  cat <<HELP
paperclip-hotpatch — Add GPT-5.5 to paperclipai/paperclip codex_local adapter

Usage (one-liner, no install):
  curl -fsSL $RAW_URL/patch.sh | bash
  curl -fsSL $RAW_URL/patch.sh | bash -s -- --dry-run
  curl -fsSL $RAW_URL/patch.sh | bash -s -- --no-restart

Flags:
  --dry-run     show what would change, write nothing
  --no-restart  patch but skip 'systemctl restart paperclip'
  -h, --help    show this help and exit

Revert (restore most recent backup):
  curl -fsSL $RAW_URL/revert.sh | bash

Repo: $REPO_URL
HELP
}

DRY_RUN=0
NO_RESTART=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-restart) NO_RESTART=1 ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

log() { printf '[%s] %s\n' "$1" "$2"; }

# --- Step 1: discover paperclipai install ---
# Supports three layouts:
#   (1) npx cache:        ~/.npm/_npx/<hash>/node_modules/paperclipai            (siblings @ ../@paperclipai/)
#   (2) global install:   /usr/local/lib/node_modules/paperclipai                (nested @ paperclipai/node_modules/@paperclipai/)
#   (3) nvm/custom:       <NPM_PREFIX>/lib/node_modules/paperclipai              (nested)

PCDIR=""

# (1) npx cache layout
NPX_ROOT="${HOME}/.npm/_npx"
if [[ -d "$NPX_ROOT" ]]; then
  for d in "$NPX_ROOT"/*/node_modules/paperclipai; do
    [[ -f "$d/package.json" ]] || continue
    PCDIR="$d"; break
  done
fi

# (2,3) global / nvm npm root
if [[ -z "$PCDIR" ]]; then
  for prefix in /usr/local/lib /usr/lib /opt/homebrew/lib "$HOME/.npm-global/lib" "$HOME/.nvm"/versions/node/*/lib; do
    cand="$prefix/node_modules/paperclipai"
    if [[ -f "$cand/package.json" ]]; then
      PCDIR="$cand"; break
    fi
  done
fi

if [[ -z "$PCDIR" ]]; then
  echo "ERROR: paperclipai not found in npx cache or any common npm global location." >&2
  echo "Searched: ~/.npm/_npx/*/node_modules/paperclipai," >&2
  echo "          /usr/local/lib/node_modules/paperclipai, /usr/lib/node_modules/paperclipai," >&2
  echo "          /opt/homebrew/lib/node_modules/paperclipai, ~/.npm-global/lib/node_modules/paperclipai," >&2
  echo "          ~/.nvm/versions/node/*/lib/node_modules/paperclipai" >&2
  exit 1
fi

PCVER=$(node -p "require('$PCDIR/package.json').version" 2>/dev/null || echo "?")
log discover "paperclipai @ $PCDIR ($PCVER)"

# Locate @paperclipai/* — try nested layout first (global install), then sibling (npx cache).
if [[ -d "$PCDIR/node_modules/@paperclipai/adapter-codex-local" ]]; then
  NM_ROOT="$PCDIR/node_modules"
elif [[ -d "$(dirname "$PCDIR")/@paperclipai/adapter-codex-local" ]]; then
  NM_ROOT="$(dirname "$PCDIR")"
else
  echo "ERROR: @paperclipai scope not found near $PCDIR" >&2
  echo "Tried: $PCDIR/node_modules/@paperclipai and $(dirname "$PCDIR")/@paperclipai" >&2
  exit 1
fi

ADAPTER_FILE="$NM_ROOT/@paperclipai/adapter-codex-local/dist/index.js"
if [[ ! -f "$ADAPTER_FILE" ]]; then
  echo "ERROR: adapter-codex-local not found at $ADAPTER_FILE" >&2
  exit 1
fi
log discover "adapter-codex-local @ $ADAPTER_FILE"

UI_ROOT="$NM_ROOT/@paperclipai/server/ui-dist"
UI_DIR="$UI_ROOT/assets"
UI_FILE=""

# Strategy 1: parse index.html entry (ground truth)
if [[ -f "$UI_ROOT/index.html" ]]; then
  ENTRY=$(grep -oE 'assets/index[^"]*\.js' "$UI_ROOT/index.html" | head -1 || true)
  if [[ -n "$ENTRY" && -f "$UI_ROOT/$ENTRY" ]]; then
    UI_FILE="$UI_ROOT/$ENTRY"
  fi
fi

# Strategy 2: pick the index-*.js chunk that contains the model strings
if [[ -z "$UI_FILE" ]]; then
  UI_FILE="$(grep -l 'gpt-5\.3-codex\|Px="gpt-5\.5"' "$UI_DIR"/index-*.js 2>/dev/null | head -1 || true)"
fi

# Strategy 3: fall back to the largest index-*.js file
if [[ -z "$UI_FILE" ]]; then
  UI_FILE="$(ls -S "$UI_DIR"/index-*.js 2>/dev/null | head -1 || true)"
fi

if [[ -z "$UI_FILE" || ! -f "$UI_FILE" ]]; then
  echo "ERROR: UI bundle not found in $UI_DIR" >&2
  exit 1
fi
log discover "ui bundle @ $UI_FILE"

# --- Step 2: pre-flight check ---
NEED_ADAPTER_DEFAULT=0
NEED_ADAPTER_FAST=0
NEED_UI_DEFAULT=0
NEED_UI_FAST=0

if grep -q 'export const DEFAULT_CODEX_LOCAL_MODEL = "gpt-5.3-codex";' "$ADAPTER_FILE"; then
  NEED_ADAPTER_DEFAULT=1
  log check 'DEFAULT_CODEX_LOCAL_MODEL = "gpt-5.3-codex" (will become "gpt-5.5")'
elif grep -q 'export const DEFAULT_CODEX_LOCAL_MODEL = "gpt-5.5";' "$ADAPTER_FILE"; then
  log check 'DEFAULT_CODEX_LOCAL_MODEL already "gpt-5.5" (skip)'
else
  log check 'DEFAULT_CODEX_LOCAL_MODEL pattern unknown — manual review required'
fi

if grep -q 'export const CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS = \["gpt-5.4"\];' "$ADAPTER_FILE"; then
  NEED_ADAPTER_FAST=1
  log check 'CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS = ["gpt-5.4"] (will add "gpt-5.5")'
elif grep -q '"gpt-5.5"' "$ADAPTER_FILE"; then
  log check 'CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS already includes "gpt-5.5" (skip)'
else
  log check 'CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS pattern unknown — manual review required'
fi

if grep -q 'Px="gpt-5.3-codex"' "$UI_FILE"; then
  NEED_UI_DEFAULT=1
  log check 'UI Px = "gpt-5.3-codex" (will become "gpt-5.5")'
elif grep -q 'Px="gpt-5.5"' "$UI_FILE"; then
  log check 'UI Px already "gpt-5.5" (skip)'
else
  log check 'UI Px pattern unknown — bundle hash changed; see references/whats-changed.md'
fi

if grep -q 'wNe=\["gpt-5.4"\]' "$UI_FILE"; then
  NEED_UI_FAST=1
  log check 'UI wNe = ["gpt-5.4"] (will add "gpt-5.5")'
elif grep -q 'wNe=\["gpt-5.4","gpt-5.5"\]' "$UI_FILE"; then
  log check 'UI wNe already includes "gpt-5.5" (skip)'
else
  log check 'UI wNe pattern unknown — bundle hash changed; see references/whats-changed.md'
fi

if (( DRY_RUN == 1 )); then
  log dry-run 'no changes written'
  exit 0
fi

TODO=$(( NEED_ADAPTER_DEFAULT + NEED_ADAPTER_FAST + NEED_UI_DEFAULT + NEED_UI_FAST ))
if (( TODO == 0 )); then
  log skip 'all targets already patched — nothing to do'
  exit 0
fi

# --- Step 3: backup ---
TS=$(date +%Y%m%d-%H%M%S)
BAK="$HOME/.paperclip-patches/$TS"
mkdir -p "$BAK"
cp "$ADAPTER_FILE" "$BAK/adapter-index.js.orig"
cp "$UI_FILE" "$BAK/ui-bundle.js.orig"
# record original paths so revert.sh can restore
printf '%s\n%s\n' "$ADAPTER_FILE" "$UI_FILE" > "$BAK/paths.txt"
log backup "saved originals → $BAK"

# --- Step 4: apply patches ---
if (( NEED_ADAPTER_DEFAULT == 1 )); then
  sed -i.bak -e 's|export const DEFAULT_CODEX_LOCAL_MODEL = "gpt-5.3-codex";|export const DEFAULT_CODEX_LOCAL_MODEL = "gpt-5.5";|' "$ADAPTER_FILE"
  rm -f "${ADAPTER_FILE}.bak"
  log patch 'adapter DEFAULT → gpt-5.5'
fi

if (( NEED_ADAPTER_FAST == 1 )); then
  sed -i.bak -e 's|export const CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS = \["gpt-5.4"\];|export const CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS = ["gpt-5.4", "gpt-5.5"];|' "$ADAPTER_FILE"
  rm -f "${ADAPTER_FILE}.bak"
  log patch 'adapter FAST list += gpt-5.5'
fi

if (( NEED_UI_DEFAULT == 1 )); then
  sed -i.bak -e 's|Px="gpt-5.3-codex"|Px="gpt-5.5"|' "$UI_FILE"
  rm -f "${UI_FILE}.bak"
  log patch 'ui Px → gpt-5.5'
fi

if (( NEED_UI_FAST == 1 )); then
  sed -i.bak -e 's|wNe=\["gpt-5.4"\]|wNe=["gpt-5.4","gpt-5.5"]|' "$UI_FILE"
  rm -f "${UI_FILE}.bak"
  log patch 'ui wNe list += gpt-5.5'
fi

# --- Step 5: verify by importing adapter ---
VERIFY=$(cd "$NM_ROOT/.." && node --input-type=module -e '
import("@paperclipai/adapter-codex-local").then(m => {
  const ok = m.DEFAULT_CODEX_LOCAL_MODEL === "gpt-5.5"
    && m.CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS.includes("gpt-5.5")
    && m.isCodexLocalKnownModel("gpt-5.5")
    && m.isCodexLocalFastModeSupported("gpt-5.5");
  process.stdout.write(ok ? "OK\n" : "FAIL\n");
  process.stdout.write(`DEFAULT=${m.DEFAULT_CODEX_LOCAL_MODEL}\n`);
  process.stdout.write(`FAST=${JSON.stringify(m.CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS)}\n`);
}).catch(e => { console.error(e); process.exit(1); });
' 2>&1) || true
log verify "$(echo "$VERIFY" | head -1)"
echo "$VERIFY" | tail -n +2 | sed 's/^/  /'

# --- Step 6: restart service if available ---
if (( NO_RESTART == 0 )) && command -v systemctl >/dev/null 2>&1 \
   && systemctl list-unit-files --no-pager 2>/dev/null | grep -q '^paperclip.service'; then
  if sudo -n true 2>/dev/null; then
    sudo systemctl restart paperclip.service
    sleep 3
    if systemctl is-active --quiet paperclip.service; then
      log restart 'paperclip.service active'
    else
      log restart 'paperclip.service failed to come up — check: journalctl -u paperclip -n 50'
      exit 1
    fi
  else
    log restart 'systemctl restart skipped (no passwordless sudo). Run manually: sudo systemctl restart paperclip'
  fi
else
  log restart 'systemd unit not present — restart paperclip manually if needed'
fi

log done "patched. revert via: curl -fsSL $RAW_URL/revert.sh | bash"
