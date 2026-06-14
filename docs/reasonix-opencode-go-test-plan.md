# Reasonix + OpenCode Go 테스트 계획

## 테스트 목표

1. OpenCode Go API endpoint가 Reasonix에서 정상 동작하는지 확인
2. `reasoning_protocol = "none"`과 `"deepseek"`의 호환성 및 품질 비교
3. **`effort` 필드가 OpenCode Go에서 받아들여지는지** 확인 (본 테스트의 핵심 질문)

---

## 자동 테스트 (권장)

```powershell
.\scripts\test-opencode-go.ps1
```

이 스크립트 하나로 Reasonix 버전, config, 자격증명, 실제 API 호출 등을 모두 자동 검증하고 최종 권장 설정까지 리포트로 출력합니다.

### 옵션

```powershell
# deepseek protocol 실험 생략 (SMOKE-01만 실행)
.\scripts\test-opencode-go.ps1 -SkipDeepseek

# 시간 제한 조정 (기본 120초)
.\scripts\test-opencode-go.ps1 -TimeoutSeconds 180

# 리포트 경로 지정
.\scripts\test-opencode-go.ps1 -ReportPath C:\temp\report.md
```

### 기본 동작

`-SkipDeepseek` 없이 실행하면 SMOKE-01, EXP-01, EXP-02를 **모두** 실행합니다.

### 동작 방식

| 단계 | 내용 | 자동 판정 기준 |
|---|---|---|
| PRE-01~02 | `reasonix` PATH 존재, Go 버전 확인 | `reasonix --version`에 `npm-v1` 또는 `1.x` 포함 |
| PRE-03~05 | credentials / config.toml 존재 확인 | 파일 존재 및 `OPENCODE_GO_API_KEY` 라인 |
| PRE-06~08 | provider 블록, base_url, reasoning_protocol 확인 | `opencode-go-deepseek`, `https://opencode.ai/zen/go/v1`, `none` |
| SMOKE-01 | `reasonix run "안녕?"` 기본 연결 확인 | 종료 코드 0, 401/402/400 오류 없음, 응답 비어 있지 않음 |
| EXP-01 | deepseek protocol only (config 임시 변경 후 자동 복원) | 400 오류 여부 |
| EXP-02 | deepseek + effort high (config 임시 변경 후 자동 복원) | 400 오류 여부 |

**실패해도 다음 테스트는 계속 진행**하며, 마지막에 요약과 함께 리포트(`reports/opencode-go-test-<timestamp>.md`)를 생성합니다.

---

## 수동 테스트 (참고용)

아래는 자동 테스트가 커버하지 못하는 `reasonix code` mode, tool call, 모델 전환 등을 직접 확인하는 케이스입니다.
자동 테스트에 문제가 있을 때 진단 용도로 사용합니다.

### 사전 준비

필요한 환경:

- **OS**: Windows 전용
- **PowerShell 7+** (`pwsh --version` 확인)
- **Node.js 18+** (`node --version` 확인)

설치 명령:

```powershell
npm install -g reasonix@next        # Go판 (1.x) — @latest는 레거시 0.x
.\scripts\setup-opencode-go.ps1     # API 키 저장 + provider 설정
```

### 테스트 매트릭스

| # | 테스트 항목 | none 예상 | deepseek 예상 |
|---|---|---|---|
| TC-01 | 단순 run | 통과 | 통과 |
| TC-02 | code mode 진입 | 통과 | 통과 |
| TC-03 | tool call round-trip | 통과 | 통과 |
| TC-04 | streaming 안정성 (긴 출력) | 통과 | 통과 |
| TC-05 | 모델 전환 (flash ↔ pro) | 통과 | 통과 |
| TC-06 | reasoning_protocol = "deepseek" 호환성 | 통과 | 정상 | ← 자동 테스트 EXP-01 |
| TC-07 | deepseek + effort 실험 | — | 가변 | ← 자동 테스트 EXP-02 |

### TC-01: 단순 run

```powershell
reasonix run "What is the capital of France? Answer in one word."
```

**합격**: 오류 없이 `Paris` 등 정답 출력.

### TC-02: code mode 진입

```powershell
cd /tmp/test-project
reasonix code --dir .
```

**합격**: TUI 진입. `/model`로 현재 모델 `opencode-go-deepseek/deepseek-v4-flash` 확인.

### TC-03: tool call round-trip

code mode에서:

```
Run `ls -la` and tell me what files you see.
```

**합격**: bash tool call 생성, 결과 출력, 에러 없음.

### TC-04: streaming 안정성

```powershell
reasonix run "Write a detailed 200-line explanation of the Linux kernel memory management system."
```

**합격**: 중간에 끊기지 않고 `[DONE]`까지 완료.

### TC-05: 모델 전환

code mode에서:

```
/model opencode-go-deepseek/deepseek-v4-pro
```

프롬프트 전송 후:

```
/model opencode-go-deepseek/deepseek-v4-flash
```

**합격**: 전환 전후 모두 정상 응답.

### TC-06: reasoning_protocol = "deepseek" 호환성

config 파일:

```toml
reasoning_protocol = "deepseek"
```

```powershell
reasonix run "What is 2+2?"
```

**판단**:

| 결과 | 결론 |
|---|---|
| 400 오류 | `"none"`만 안정적 |
| 정상 응답 | `"deepseek"`도 사용 가능 |
| reasoning 출력 표시 | 품질 이점 있음 |

### TC-07: deepseek + effort

```toml
reasoning_protocol = "deepseek"
effort = "high"
```

```powershell
reasonix run "Write a complex Python script for a multi-threaded web scraper with proper error handling."
```

**합격**: `"none"`과 비교해 응답 품질 동등 이상.

---

## 종료 기준

1. ❏ `reasonix@next` (Go판 1.x) 설치 완료
2. ❏ `setup-opencode-go.ps1` 자동 설정 통과
3. ❏ `test-opencode-go.ps1` SMOKE-01 PASS (기본 연결)
4. ❏ `test-opencode-go.ps1` EXP-01/EXP-02 판정 완료 (deepseek protocol + effort)
5. ❏ 최종 권장 설정 결정:

| SMOKE-01 | EXP-01 | EXP-02 | 권장 |
|---|---|---|---|
| FAIL | — | — | config/API key/provider 문제 |
| PASS | FAIL | — | `reasoning_protocol = "none"` 유지 |
| PASS | PASS | FAIL | `reasoning_protocol = "deepseek"`, `effort`는 생략 |
| PASS | PASS | PASS | `reasoning_protocol = "deepseek"` 기본 사용, `effort = "high"`는 선택 옵션 |
