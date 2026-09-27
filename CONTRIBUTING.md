# 기여 안내

버그 제보와 코드·문서 개선을 환영합니다. 큰 기능 변경은 먼저 Issue로 문제와 제안을 나눠 주세요.

## 버그 제보와 Pull request

1. 기존 Issues와 [지원 환경](INSTALL.md#지원-범위)을 확인합니다.
2. 앱 버전·재현 순서·기대한 결과·실제 결과를 적습니다.
3. 직접 수정한다면 한 PR에 한 가지 목적을 담고, 실행한 검사를 적습니다.

개인 자료와 API 키 대신 짧은 재현 예시를 사용하세요. 보안 문제는 [비공개로 제보](SECURITY.md)해 주세요.
기여를 반영할 때 저자와 출처를 보존합니다.

## 소스에서 빌드

Apple Silicon Mac과 macOS 26 SDK가 포함된 Xcode 또는 Command Line Tools가 필요합니다.
앱을 사용하려면 [배포 앱 설치](INSTALL.md)로 시작할 수 있습니다.

```bash
./scripts/fetch-model.sh
CLONIE_SIGN_ID=- ./build.sh --app-only --include-model
open Clonie.app
```

모델 준비에는 외부 다운로드와 변환 도구 설치로 수 GB가 필요할 수 있습니다.
위 명령은 로컬 ad-hoc 서명을 사용합니다. 개발용 인증서를 사용하려면 `CLONIE_SIGN_ID`에 인증서 식별자를 지정하세요.

## 검사

Swift 검사 외에 Python 3와 Node.js가 필요합니다.

```bash
swift test
python3 scripts/test-install.py
node --test tests/clonie-plugin.test.mjs
python3 scripts/sync-clonie-plugin.py --check
python3 tests/check_public_repo.py
python3 scripts/check-public-repo.py --root .
```

모델을 사용하는 임베딩 검사는 `./scripts/fetch-model.sh`로 준비한 뒤 실행합니다.

```bash
CLONIE_REQUIRE_EMBEDDING_MODEL=1 swift test --filter ClonieEmbeddingTests
```

공개 CI는 문서 링크와 비밀정보를 검사합니다. Swift·플러그인 검사와 앱 실행은 로컬에서 확인하고, PR에 결과를 적어 주세요.

## 플러그인 개발

Clonie 앱을 설치한 뒤 소스 저장소 루트에서 개발 중인 플러그인을 등록할 수 있습니다.

Codex:

```bash
codex plugin marketplace add .
codex plugin add clonie@clonie
```

Claude Code:

```bash
claude plugin marketplace add .
claude plugin install clonie@clonie
```

- `plugins/clonie/`의 Codex·Claude Code manifest가 같은 MCP와 스킬을 사용합니다.
- 스킬 원본은 `.agents/skills/`의 `clonie`, `clonie-init`, `clonie-session-record`입니다.
  수정 후 `python3 scripts/sync-clonie-plugin.py`로 배포본을 갱신합니다.
- MCP는 설치된 앱의 `clonie-mcp`를 사용하고, 앱이 선택한 저장소에 연결합니다.
  격리 시험에서는 `CLONIE_APP_PATH`와 `CLONIE_VAULT`에 시험용 앱·폴더의 절대 경로를 지정할 수 있습니다.
- 앱은 `proposal-v1` 변경 계약을 지원해야 합니다. `vault_write`는 승인 대기 제안을 만들며,
  원문 저장은 앱 승인 뒤에 이루어집니다. 시험에는 개인 자료 대신 별도 폴더를 사용하세요.

## 릴리스와 문서

사용법이 바뀌면 해당 안내와 `CHANGELOG.md`를 함께 갱신합니다. README는 제품 소개와 첫 사용,
`INSTALL.md`는 앱 설치·업데이트, `plugins/clonie/README.md`는 외부 AI 연결을 설명합니다.

버전별 변경은 `CHANGELOG.md`, 배포 파일과 상세 릴리스 노트는 [GitHub Releases](https://github.com/qoal1201/clonie-preview/releases)에서 관리합니다.
앱 배포 시 버전·URL·SHA-256을 `scripts/install.sh`와 `Casks/clonie.rb`에 함께 반영합니다.
이미 공개한 파일과 태그는 바꾸지 않습니다.

## 라이선스

신규 자체 코드의 기여물은 [PolyForm Perimeter 1.0.1](LICENSE)을 따릅니다.
제3자 코드는 원래 출처·라이선스·고지를 보존하세요. 기존 MIT 권리와 적용 범위는
[LICENSING.md](LICENSING.md), 프로젝트 출처는 [HISTORY.md](HISTORY.md)를 참고하세요.
