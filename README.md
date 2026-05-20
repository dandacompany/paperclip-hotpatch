# paperclip-hotpatch

> One-liner hotpatch that adds **GPT-5.5** to the `codex_local` adapter of [paperclipai/paperclip](https://github.com/paperclipai/paperclip) — server side and minified UI bundle, in one shot.

Codex CLI 0.130+ already recognises `gpt-5.5`. Paperclip's adapter metadata simply hasn't been updated upstream: seven PRs to add `gpt-5.5` are sitting open and unmerged ([#4357](https://github.com/paperclipai/paperclip/pull/4357), [#4646](https://github.com/paperclipai/paperclip/pull/4646), [#5022](https://github.com/paperclipai/paperclip/pull/5022), [#5575](https://github.com/paperclipai/paperclip/pull/5575), [#5898](https://github.com/paperclipai/paperclip/pull/5898), [#6044](https://github.com/paperclipai/paperclip/pull/6044), [#6045](https://github.com/paperclipai/paperclip/pull/6045)). This patch closes that gap on your machine in 30 seconds.

---

## Install (one-liner, no install)

### Apply

```bash
curl -fsSL https://raw.githubusercontent.com/dandacompany/paperclip-hotpatch/main/patch.sh | bash
```

### Dry-run (preview, write nothing)

```bash
curl -fsSL https://raw.githubusercontent.com/dandacompany/paperclip-hotpatch/main/patch.sh | bash -s -- --dry-run
```

### Revert (restore most recent backup)

```bash
curl -fsSL https://raw.githubusercontent.com/dandacompany/paperclip-hotpatch/main/revert.sh | bash
```

---

## What changes

| Target | Identifier | Before | After |
|---|---|---|---|
| `@paperclipai/adapter-codex-local/dist/index.js` | `DEFAULT_CODEX_LOCAL_MODEL` | `"gpt-5.3-codex"` | `"gpt-5.5"` |
| `@paperclipai/adapter-codex-local/dist/index.js` | `CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS` | `["gpt-5.4"]` | `["gpt-5.4", "gpt-5.5"]` |
| `@paperclipai/server/ui-dist/assets/index-*.js` (minified) | `Px` (default constant) | `"gpt-5.3-codex"` | `"gpt-5.5"` |
| `@paperclipai/server/ui-dist/assets/index-*.js` (minified) | `wNe` (fast-mode list) | `["gpt-5.4"]` | `["gpt-5.4","gpt-5.5"]` |

Full change spec: [`docs/whats-changed.md`](docs/whats-changed.md).

---

## Docker / Hostinger note

If you're running paperclip as a Docker container (e.g. Hostinger's `ghcr.io/hostinger/hvps-paperclip` image), call the patch from **inside** the container, **as root**:

```bash
docker exec -u root <container-name> sh -c '
  curl -fsSL https://raw.githubusercontent.com/dandacompany/paperclip-hotpatch/main/patch.sh | bash
'
docker restart <container-name>
```

Why `-u root`: those images default to a non-root user (e.g. `node`) while the `paperclipai` files under `/usr/local/lib/node_modules/` are owned by root. `sed -i` needs write access to the directory for its temp file.

The script auto-detects both layouts — npx cache (`~/.npm/_npx/<hash>/...`) and global install (`/usr/local/lib/node_modules/...` with `@paperclipai/*` nested inside `paperclipai/node_modules/`).

Verified on `ghcr.io/hostinger/hvps-paperclip:latest` (paperclipai 2026.517.0) on Hostinger VPS.

---

## How it works

The patch script:

1. **Discovers** the active paperclipai install by scanning `~/.npm/_npx/<hash>/node_modules/paperclipai`.
2. **Locates** the UI entry chunk by parsing `ui-dist/index.html` (handles changing bundle hashes across paperclipai versions).
3. **Backs up** target files to `~/.paperclip-patches/<timestamp>/` before touching them.
4. **Patches** four constants via deterministic `sed` substitutions — idempotent (running it twice is safe; second run reports "already patched").
5. **Verifies** by importing the adapter via Node ESM and asserting `isCodexLocalKnownModel("gpt-5.5") === true` and `isCodexLocalFastModeSupported("gpt-5.5") === true`.
6. **Restarts** `paperclip.service` if systemd is present and passwordless sudo is available; otherwise prints the manual restart command.

No network calls beyond `curl`. No persistent install — everything lives in `~/.paperclip-patches/` (backups) and the npx cache.

---

## Verification after patching

```bash
node --input-type=module -e '
import("@paperclipai/adapter-codex-local").then(m => {
  console.log("DEFAULT:", m.DEFAULT_CODEX_LOCAL_MODEL);
  console.log("FAST:", m.CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS);
  console.log("known(gpt-5.5):", m.isCodexLocalKnownModel("gpt-5.5"));
  console.log("fast(gpt-5.5):", m.isCodexLocalFastModeSupported("gpt-5.5"));
})'
```

Expected:

```
DEFAULT: gpt-5.5
FAST: [ 'gpt-5.4', 'gpt-5.5' ]
known(gpt-5.5): true
fast(gpt-5.5): true
```

Then refresh the paperclip UI (hard reload) and `gpt-5.5` should appear in the `codex_local` agent model dropdown.

---

## Caveat — volatility

`~/.npm/_npx/<hash>/` may be overwritten the next time `npx` fetches a newer paperclipai version. To make the patch durable, pin the paperclipai version in your systemd unit:

```ini
ExecStart=/usr/bin/npx --yes paperclipai@<current-version> run --no-repair
```

This stops npx from re-downloading and wiping your patched files. Re-run the patch after intentional upgrades.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `[discover] paperclipai not found` | npx cache not populated yet. Start paperclip once (`systemctl start paperclip`) then retry. |
| Dropdown still doesn't show `gpt-5.5` after patch | Browser cache. Hard reload (`Cmd+Shift+R` / `Ctrl+Shift+R`). |
| `Command not found in PATH: "codex"` in paperclip logs | systemd unit's `PATH` doesn't include the location of the `codex` binary. Add a drop-in at `/etc/systemd/system/paperclip.service.d/path.conf` that extends `PATH` to cover `~/.npm-global/bin` (or wherever you installed `@openai/codex`). |
| `UI Px pattern unknown` | paperclipai bundled with different esbuild identifiers. See [`docs/whats-changed.md`](docs/whats-changed.md) for the fallback (grep model strings directly and write a custom sed line). |

---

## 한국어 노트

이 패치는 **paperclipai/paperclip 운영 중인 사람**을 위한 것입니다. upstream에는 같은 패치를 시도한 PR이 7개 누적되어 있지만 머지가 진행되지 않고 있어, 그동안 자기 머신에 한해 GPT-5.5를 사용할 수 있게 만드는 우회입니다. Codex CLI 0.130 이상에서 `gpt-5.5`가 정상 인식되므로 paperclip의 어댑터 메타데이터만 손보면 즉시 동작합니다.

자세한 배경과 사용 시나리오 정리: <https://edu-n8n.dante-labs.com/webhook/paperclip-gpt55-patch>

---

## Related upstream

- Issue [#4481](https://github.com/paperclipai/paperclip/issues/4481) — "Add ChatGPT 5.5"
- Issue [#4405](https://github.com/paperclipai/paperclip/issues/4405) — "No model auto-detection"
- PR [#5898](https://github.com/paperclipai/paperclip/pull/5898) — closest to this patch's surface (Claude Opus 4.7 authored)

---

## License

MIT — see [`LICENSE`](LICENSE).

## Author

[Dante (단테)](https://dante-labs.com) · Dante Labs · [@dante-labs](https://youtube.com/@dante-labs)
