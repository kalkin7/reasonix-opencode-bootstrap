# Reasonix + OpenCode Go 설정법

이 문서는 Reasonix를 OpenCode Go 구독의 DeepSeek V4 Flash / V4 Pro 전용 CLI처럼 사용하는 방법을 설명합니다.

세팅 스크립트 하나로 API 키 저장 + provider 설정 + 기본 모델 변경까지 자동 처리됩니다.

## 전제 조건

### 시스템 요구사항

- **OS**: Windows 전용 (macOS/Linux 미지원)
- **PowerShell 7+** (`pwsh --version`으로 확인)
  - Windows PowerShell 5.1은 사용 불가
  - 설치: `winget install Microsoft.PowerShell` 또는 [GitHub](https://github.com/PowerShell/PowerShell/releases)
- **Node.js 18+** (`node --version`으로 확인)
  - npm을 통해 Reasonix를 설치하기 위해 필요

### 소프트웨어 요구사항

- Reasonix Go판 사용 (Go 재작성판, 버전 1.x)
- [OpenCode Go](https://opencode.ai/docs/go/) 구독 완료 및 API 키 발급

### Reasonix Go판 설치 주의

2026-06 기준, npm `latest` 태그는 아직 레거시 TypeScript 0.x 라인을 가리킬 수 있으므로 `next`를 명시해야 합니다.

```powershell
npm uninstall -g reasonix
npm install -g reasonix@next
reasonix --version
```

정상 예시:

```text
reasonix npm-v1.6.0-rc.1
```

레거시 버전 (`0.53.2`)에서는 이 문서의 OpenCode Go provider 설정이 동작하지 않습니다.

대안으로 GitHub Release에서 Windows zip을 받을 수도 있습니다.

```text
https://github.com/esengine/DeepSeek-Reasonix/releases
```

## 1. 자동 설정 (권장)

```powershell
.\scripts\setup-opencode-go.ps1
```

이 스크립트가 다음을 모두 처리합니다:

1. OpenCode Go API key를 마스킹 입력받음
2. `%APPDATA%\reasonix\credentials`에 저장
3. `%APPDATA%\reasonix\config.toml`에 OpenCode Go provider 추가
4. 기본 모델을 `opencode-go-deepseek`로 설정
5. 기존 config는 자동 백업 (`config.toml.bak-YYYYMMDD-HHMMSS`)

### 옵션

기본 모델 변경 없이 provider만 추가:

```powershell
.\scripts\setup-opencode-go.ps1 -NoDefault
```

키는 이미 저장돼 있고 provider 설정만 추가/갱신:

```powershell
.\scripts\setup-opencode-go.ps1 -SkipKeyPrompt
```

## 2. 실행

스크립트 한 번 실행 후에는 일반 Reasonix 명령을 그대로 사용합니다.

```powershell
reasonix code
```

```powershell
reasonix run "hello"
```

```powershell
reasonix code --dir C:\path\to\project
```

### 모델 전환

Reasonix 내에서 `/model` 명령어로 전환:

```
/model opencode-go-deepseek/deepseek-v4-pro
```

다시 flash로:

```
/model opencode-go-deepseek/deepseek-v4-flash
```

## 3. 설정 결과 확인

스크립트가 생성한 config 파일:

```powershell
Get-Content -LiteralPath "$env:APPDATA\reasonix\config.toml"
```

포함된 provider 블록:

```toml
default_model = "opencode-go-deepseek"

[[providers]]
name = "opencode-go-deepseek"
kind = "openai"
base_url = "https://opencode.ai/zen/go/v1"
models = ["deepseek-v4-flash", "deepseek-v4-pro"]
default = "deepseek-v4-flash"
api_key_env = "OPENCODE_GO_API_KEY"
context_window = 1000000
reasoning_protocol = "deepseek"
price = { cache_hit = 0.0028, input = 0.14, output = 0.28, currency = "$" }
```

credentials 파일:

```powershell
Get-Content -LiteralPath "$env:APPDATA\reasonix\credentials"
```

## 4. 수동 설정 (참고)

자동 스크립트를 쓰지 않고 직접 config를 편집하는 경우입니다.  
스크립트가 이미 다 해주므로 보통 필요하지 않습니다.

### API 키 저장

Reasonix 글로벌 credentials 파일 (`%APPDATA%\reasonix\credentials`)에:

```env
OPENCODE_GO_API_KEY=oc-go-xxxxxxxx
```

또는 프로젝트 `.env`:

```env
OPENCODE_GO_API_KEY=oc-go-xxxxxxxx
```

### Config 파일

사용자 글로벌 config (`%APPDATA%\reasonix\config.toml`) 또는 프로젝트 `reasonix.toml`에:

```toml
default_model = "opencode-go-deepseek"

[[providers]]
name = "opencode-go-deepseek"
kind = "openai"
base_url = "https://opencode.ai/zen/go/v1"
models = ["deepseek-v4-flash", "deepseek-v4-pro"]
default = "deepseek-v4-flash"
api_key_env = "OPENCODE_GO_API_KEY"
context_window = 1000000
reasoning_protocol = "deepseek"
price = { cache_hit = 0.0028, input = 0.14, output = 0.28, currency = "$" }
```

| 필드 | 설명 |
|---|---|
| `base_url` | OpenCode Go endpoint. Reasonix가 내부적으로 `/chat/completions` 자동 추가 |
| `reasoning_protocol` | `"deepseek"` 권장. `"none"`은 문제 발생 시 fallback |

## 5. reasoning_protocol 가이드

| 설정 | 용도 | 위험도 |
|---|---|---|
| `"deepseek"` | **권장**. `thinking`/`reasoning_effort` 전송. 호환성 테스트 통과 | 낮음 |
| `"none"` | fallback. 문제 발생 시 `thinking`/`reasoning_effort` 미전송 | 낮음 |

`effort = "high"`는 기본 config에 넣지 않습니다. OpenCode Go가 `effort = "high"` 수용 여부는 테스트로 확인됐지만, 모든 요청에 high effort를 강제하는 것은 비용/응답시간 측면에서 기본값으로 적합하지 않습니다. 필요할 때만 수동으로 추가해 사용합니다.

### reasoning_protocol 실험 방법

현재 기본 설정 `reasoning_protocol = "deepseek"`입니다. 수동으로 전환하는 방법입니다.

**1. 기본 안정성 확인**

```powershell
reasonix run "say hello"
```

정상 기준: DeepSeek 402 오류 없이 OpenCode Go 키로 응답 수신.

**2. 간단 추론 테스트**

```powershell
reasonix run "Solve this carefully: If a train travels 120 km in 1.5 hours, what is its average speed?"
```

정상 기준: 올바른 답변 (80 km/h). 오류 없음.

**3. 코드 작업 테스트**

```powershell
reasonix run "Write a Python function that checks whether a string is a palindrome. Include 3 test cases."
```

정상 기준: 코드 생성 정상.

**4. code mode tool 테스트**

```powershell
reasonix code
```

Reasonix 내에서:

```text
List the files in this directory and summarize what this project contains.
```

정상 기준: 파일/디렉터리 읽기 tool 정상 동작.

**5. `deepseek` 모드 실험**

config 파일을 편집:

```powershell
notepad "$env:APPDATA\reasonix\config.toml"
```

`reasoning_protocol`을 변경:

```toml
reasoning_protocol = "deepseek"
effort = "high"
```

저장 후 새 세션에서:

```powershell
reasonix run "Think carefully and solve: A shop gives 20% off, then charges 10% tax. What is the final price of a $100 item?"
```

**결과 판단**

| 결과 | 판단 |
|---|---|
| 정상 응답 | OpenCode Go가 DeepSeek reasoning 필드를 받아줌. `deepseek` 기본 사용 |
| 400 Bad Request | OpenCode Go가 `thinking`/`reasoning_effort` 거부. `none`으로 fallback |
| 응답은 되지만 품질 차이 없음 | `deepseek` 실익 불확실. 안정성 기준 `none` 사용 가능 |

**6. 테스트 후 원복**

```toml
reasoning_protocol = "none"
```

`effort = "high"` 줄은 제거 또는 주석 처리.  
**참고**: `effort`는 기본값이 아니라 실험/수동 옵션입니다. OpenCode Go가 수용하는 것은 확인됐지만, 모든 요청에 고정할 필요는 없습니다.

**권장**: 기본 설정은 `reasoning_protocol = "deepseek"`입니다. 400 오류가 발생하는 경우에만 `"none"`으로 내리면 됩니다.

## 6. 예상 문제 및 해결

| 증상 | 원인 | 해결 |
|---|---|---|
| 401 인증 실패 | API 키가 올바르지 않거나 만료됨 | 키 재발급 후 `setup-opencode-go.ps1` 재실행 |
| 403 인증 실패 | 구독 상태 문제 | 콘솔에서 구독 상태 확인 |
| 404 Not Found | `base_url`이 잘못됨 | 스크립트가 자동 설정하므로 발생하지 않음 |
| 400 Bad Request | `reasoning_protocol = "deepseek"` 호환성 문제 | `"none"`으로 변경 |
| provider 중복 | 수동으로 여러 번 추가 | 스크립트 재실행 시 자동 중복 제거 |

## 7. 참고 링크

- [Reasonix 공식 저장소](https://github.com/esengine/DeepSeek-Reasonix)
- [OpenCode Go 문서](https://opencode.ai/docs/go/)
- [OpenCode Go API key](https://opencode.ai/auth)
