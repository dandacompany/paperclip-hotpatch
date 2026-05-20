# Patch 상세 명세

이 패치가 **정확히 어떤 상수**를 **어떻게** 바꾸는지 정리한 문서. paperclipai 버전이 달라져 자동 패치가 실패하면 이 문서를 참고해 수동으로 적용하세요.

## 대상 1 — Adapter 원본 (ESM)

**파일**: `<NM>/@paperclipai/adapter-codex-local/dist/index.js`
(`<NM>` = `~/.npm/_npx/<hash>/node_modules`)

### 변경 ①: 기본 모델 상수

```diff
-export const DEFAULT_CODEX_LOCAL_MODEL = "gpt-5.3-codex";
+export const DEFAULT_CODEX_LOCAL_MODEL = "gpt-5.5";
```

이 상수는 두 가지 효과를 가집니다:

1. 새 codex_local 에이전트 생성 시 `adapterConfig.model`의 기본값
2. 같은 파일의 `models` 배열에 `{ id: DEFAULT_CODEX_LOCAL_MODEL, label: DEFAULT_CODEX_LOCAL_MODEL }` 엔트리가 있어 **dropdown에도 자동 propagation**

### 변경 ②: Fast mode 화이트리스트

```diff
-export const CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS = ["gpt-5.4"];
+export const CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS = ["gpt-5.4", "gpt-5.5"];
```

`isCodexLocalFastModeSupported()`가 이 배열을 참조합니다. 여기 없으면 `fastMode: true`를 설정해도 `service_tier="fast"` / `features.fast_mode=true` 가 codex CLI 인자에 추가되지 않습니다.

## 대상 2 — Server route (수정 불필요)

**파일**: `<NM>/@paperclipai/server/dist/routes/agents.js`

```js
import { DEFAULT_CODEX_LOCAL_BYPASS_APPROVALS_AND_SANDBOX, DEFAULT_CODEX_LOCAL_MODEL, } from "@paperclipai/adapter-codex-local";
// ...
next.model = DEFAULT_CODEX_LOCAL_MODEL;
```

ESM import이므로 대상 1만 수정해도 자동 반영됩니다.

## 대상 3 — UI bundle (minified)

**파일**: `<NM>/@paperclipai/server/ui-dist/assets/index-*.js`
(hash 부분은 paperclipai 빌드마다 달라짐 — `index-DKYfatQR.js` 등)

UI는 React 빌드 결과물로, adapter의 모델 리스트가 minified 형태로 **인라인 복제**되어 있습니다. 식별자도 변형:

| 의미 | adapter 원본 식별자 | UI 번들 식별자 |
|---|---|---|
| 기본 모델 상수 | `DEFAULT_CODEX_LOCAL_MODEL` | `Px` |
| Fast mode 화이트리스트 | `CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS` | `wNe` |
| 모델 배열 | `models` | `NNe` |
| Bypass approvals default | `DEFAULT_CODEX_LOCAL_BYPASS_APPROVALS_AND_SANDBOX` | `QC` |

### 변경 ③: UI 기본 모델

```diff
-const Px="gpt-5.3-codex",QC=!0,wNe=["gpt-5.4"];
+const Px="gpt-5.5",QC=!0,wNe=["gpt-5.4","gpt-5.5"];
```

`Px`만 치환하면 `NNe` 배열의 `{id:Px,label:Px}` 엔트리도 자동으로 5.5가 됩니다 (dropdown 자동 갱신).

## 검증 명령

```bash
node --input-type=module -e '
import("@paperclipai/adapter-codex-local").then(m => {
  console.log("DEFAULT:", m.DEFAULT_CODEX_LOCAL_MODEL);
  console.log("FAST:", m.CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS);
  console.log("Models:");
  m.models.forEach(x => console.log(" -", x.id, "|", x.label));
  console.log("known(gpt-5.5):", m.isCodexLocalKnownModel("gpt-5.5"));
  console.log("fast(gpt-5.5):", m.isCodexLocalFastModeSupported("gpt-5.5"));
})'
```

기대 출력:
```
DEFAULT: gpt-5.5
FAST: [ 'gpt-5.4', 'gpt-5.5' ]
Models:
 - gpt-5.4 | gpt-5.4
 - gpt-5.5 | gpt-5.5
 - gpt-5.3-codex-spark | gpt-5.3-codex-spark
 - gpt-5 | gpt-5
 - o3 | o3
 - o4-mini | o4-mini
 - gpt-5-mini | gpt-5-mini
 - gpt-5-nano | gpt-5-nano
 - o3-mini | o3-mini
 - codex-mini-latest | Codex Mini
known(gpt-5.5): true
fast(gpt-5.5): true
```

`gpt-5.3-codex`(non-spark)는 dropdown에서 사라집니다. 5.3-codex를 별도 엔트리로 유지하고 싶다면 adapter `index.js`의 models 배열에 명시적으로 다음 줄을 추가하세요:

```js
{ id: "gpt-5.3-codex", label: "gpt-5.3-codex" },
```

(UI 번들에도 동일하게 minified 형태로 삽입해야 하며, JSON 배열 길이 변경 위험이 있어 추천하지 않습니다.)

## 패치 패턴이 안 맞을 때

`grep`으로 직접 확인:

```bash
NM=~/.npm/_npx/*/node_modules
grep -n 'DEFAULT_CODEX_LOCAL_MODEL\|CODEX_LOCAL_FAST_MODE' $NM/@paperclipai/adapter-codex-local/dist/index.js
grep -o 'Px="gpt-5\.[^"]*"\|wNe=\["gpt-5\.[^]]*\]' $NM/@paperclipai/server/ui-dist/assets/index-*.js
```

상수 이름(`Px`, `wNe`)이 다르다면 UI 번들이 다른 esbuild 시드로 빌드된 것입니다. 원본 식별자(`DEFAULT_CODEX_LOCAL_MODEL`, `CODEX_LOCAL_FAST_MODE_SUPPORTED_MODELS`)는 minified bundle에 그대로 남지 않으므로, 모델 문자열 자체(`"gpt-5.3-codex"`, `"gpt-5.4"`)로 검색해 둘러싼 컨텍스트를 확인한 뒤 수동 sed 명령을 새로 작성해야 합니다.

## 왜 npx 캐시를 직접 건드리나

paperclipai는 `npx --yes paperclipai run`으로 실행되며, 패키지 매니페스트(`@paperclipai/adapter-codex-local`)는 paperclipai의 의존성으로 동봉됩니다. 따라서:

- **글로벌 install 시도(`npm install -g paperclipai`)는 동일 패키지 트리를 만들지만 npx 캐시와 분리되어 효과 없음**
- 운영 시점에 paperclip이 실제로 로드하는 모듈은 npx 캐시 안의 것
- 따라서 핫패치 대상도 npx 캐시 안의 파일

영구화는 systemd `ExecStart`에 paperclipai 버전을 핀(`paperclipai@2026.517.0`)해 캐시 무효화를 막는 방식이 가장 안정적입니다.
