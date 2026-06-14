# Reasonix + OpenCode Go Bootstrap

**Reasonix** (Go rewrite)를 **OpenCode Go** API의 DeepSeek V4 Flash / V4 Pro 모델 전용 CLI로 설정하고, **agent-skills** 스토어를 한 번에 설치하는 자동화 스크립트 모음입니다.

---

## 🚀 원클릭 설치 (새 머신)

**방법 1 — GitHub 클론 후 실행 (권장)**

```powershell
git clone https://github.com/kalkin7/reasonix-opencode-bootstrap.git
cd reasonix-opencode-bootstrap
.\scripts\bootstrap-all.ps1
```

**방법 2 — 원격 원라인 (PowerShell 7+)**

```powershell
irm https://raw.githubusercontent.com/kalkin7/reasonix-opencode-bootstrap/main/scripts/bootstrap-all.ps1 | iex
```

스크립트가 자동으로:
| 단계 | 내용 |
|------|------|
| 1/7 | 필수 구성요소 확인 (PowerShell 7+, Node.js 18+) |
| 2/7 | Reasonix Go 설치 (`npm install -g reasonix@next`) |
| 3/7 | OpenCode Go API 키 입력 + provider 설정 |
| 4/7 | `agent-skills` 저장소 클론 (GitHub) |
| 5/7 | `setup_skills.ps1 Bootstrap` 실행 |
| 6/7 | `setup_skills.ps1 Verify` 실행 |
| 7/7 | Smoke Test (`reasonix run "hello"`) |

---

## ⚙️ `bootstrap-all.ps1` 옵션

통합 부트스트랩은 다양한 상황에 맞게 옵션을 조정할 수 있습니다:

| 옵션 | 설명 |
|------|------|
| `-SkipReasonixInstall` | Reasonix 설치 단계 생략 (이미 설치된 경우) |
| `-SkipKeyPrompt` | API 키 입력 생략 (이미 저장된 경우) |
| `-NoVerify` | 최종 Smoke Test 생략 |
| `-SkillStorePath "D:\my-skills"` | 스킬 스토어 위치 지정 |
| `-GitCloneUrl "https://github.com/..."` | 다른 스킬 저장소 URL 사용 |

```powershell
# 이미 Reasonix 설치됨 → provider + skill store만 설정
.\scripts\bootstrap-all.ps1 -SkipReasonixInstall

# 재빌드만 (설정 유지)
.\scripts\bootstrap-all.ps1 -SkipReasonixInstall -SkipKeyPrompt
```

## 📦 구성 요소

| 파일 | 설명 |
|------|------|
| `scripts/bootstrap-all.ps1` | **통합 부트스트랩** — 모든 단계를 한 번에 실행 |
| `scripts/setup-opencode-go.ps1` | OpenCode Go provider + API 키 설정 전용 |
| `scripts/test-opencode-go.ps1` | 연결성 / provider / 모델 전환 테스트 |
| `docs/reasonix-opencode-go-setup.md` | 상세 설정 가이드 (한국어) |

---

## ⚙️ 개별 스크립트 사용

### OpenCode Go provider만 추가 (이미 Reasonix가 설치된 경우)

```powershell
.\scripts\setup-opencode-go.ps1
```

| 옵션 | 설명 |
|------|------|
| `-NoDefault` | provider만 추가, 기본 모델 변경 안 함 |
| `-SkipKeyPrompt` | API 키 저장 생략 (이미 저장된 경우) |
| `-UseDeepseekReasoning` | `reasoning_protocol = "deepseek"` 사용 (thinking 필드) |

### 스킬 스토어만 재설정

```powershell
& "$env:USERPROFILE\agent-skills\setup_skills.ps1" Bootstrap
& "$env:USERPROFILE\agent-skills\setup_skills.ps1" Verify
```

---

## 🔄 스킬 동기화

스킬 스토어(`agent-skills`)는 GitHub + Google Drive로 동기화됩니다.

```powershell
cd ~\agent-skills
git pull --rebase origin main
.\setup_skills.ps1 Bootstrap
```

자세한 내용은 `setup_skills.ps1` 헤더를 참고하세요.

---

## 🐛 문제 해결

| 증상 | 해결 |
|------|------|
| 401 인증 실패 | API 키 재발급 후 `setup-opencode-go.ps1` 재실행 |
| 400 Bad Request | `-UseDeepseekReasoning` 없이 실행 (기본: `reasoning_protocol = "none"`) |
| `reasonix` 명령 없음 | `npm install -g reasonix@next` 로 Go판 설치 |
| 모델 전환 | Reasonix 내에서 `/model opencode-go-deepseek/deepseek-v4-pro` |
