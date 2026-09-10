# 설치 안내

Clonie 공개 알파는 **macOS 26 이상, Apple Silicon Mac**에서 실행합니다. Windows와 Intel Mac은
지원하지 않습니다. 앱 번들 파일 이름은 현재 `Ghostbar.app`입니다.

## 권장 설치: Homebrew

Homebrew가 있으면 다음 순서로 설치합니다.

```bash
brew tap qoal1201/clonie-preview https://github.com/qoal1201/clonie-preview
brew install --cask qoal1201/clonie-preview/clonie
```

동봉 모델이 포함된 릴리스 앱을 설치하며, 설치가 끝나도 앱은 자동으로 실행되지 않습니다.
같은 Mac의 격리 설치에서 tap 등록, 릴리스 다운로드·SHA-256 확인, 별도 디렉터리 설치,
설치한 실행 파일 SHA와 codesign 확인까지 통과했습니다. 앱은 실행하지 않았으므로 Gatekeeper 승인,
개발자 신뢰 설정, TCC와 음성 권한은 이 검증에 포함되지 않았습니다. 다른 Mac의 첫 설치는 아직 검증하지 않았습니다.

## Homebrew 없이 설치

공개 저장소의 `main`에 있는 설치 스크립트를 읽을 수 있는 임시 경로에 내려받아 실행합니다.

```bash
curl -fL https://raw.githubusercontent.com/qoal1201/clonie-preview/main/scripts/install.sh -o /tmp/clonie-install.sh
bash /tmp/clonie-install.sh
```

스크립트는 `preview-20260910`으로 고정된 동봉 모델 앱과 SHA-256을 확인하고 기본 경로
`~/Applications/Ghostbar.app`에 설치합니다. 같은 경로에 기존 앱이 있으면 덮어쓰지 않고 중단합니다.
설치 후 자동 실행도 하지 않습니다.

## ZIP으로 설치

[preview-20260910 릴리스](https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260910)에서
Apple Silicon용 ZIP을 내려받아 압축을 풉니다. `Ghostbar.app`을 응용 프로그램 폴더로 옮긴 뒤 엽니다.
릴리스 앱에는 모델이 동봉되어 있어 Python이나 Xcode를 설치하지 않아도 기본 사용을 시작할 수 있습니다.

## 첫 실행

1. `Ghostbar.app`을 엽니다.
2. macOS가 출처를 확인할 수 없다고 표시하면 시스템 설정 → 개인정보 보호 및 보안에서 앱을 확인하고
   **확인 없이 열기(Open Anyway)**를 직접 승인합니다.
3. 앱에서 Markdown 폴더를 선택합니다. 중요한 자료는 복사본으로 먼저 연결하세요.
4. 음성 연습을 사용할 때는 마이크·화면 기록 권한과 Apple 음성 모델 준비를 직접 승인합니다.

Gatekeeper 승인과 음성 권한·모델 준비는 사용자의 명시적인 선택이 필요한 단계입니다. 설치기는 이 승인들을
대신 수행하지 않습니다.

## 문제가 생겼을 때

- macOS 26 이상인지, Apple Silicon Mac인지 확인합니다.
- 앱 이름이 `Ghostbar.app`인지 확인합니다. 새 앱 번들 이름은 아직 정하지 않았습니다.
- Gatekeeper 메시지의 **확인 없이 열기**를 승인했는지 확인합니다.
- 설치 위치에 기존 `Ghostbar.app`이 있으면 설치기는 덮어쓰지 않으므로, 기존 파일을 보존한 뒤 원하는
  설치 경로를 정리해 다시 시도합니다.
- 다른 Mac 설치는 아직 검증하지 않았습니다. Mac 모델, macOS 버전, 오류 문구를 [Issues](https://github.com/qoal1201/clonie-preview/issues)에 남겨 주세요.

## 개인정보

Markdown과 `.clonie` 색인·입력 기록은 연결한 폴더에 남습니다. 외부 AI 자료 정리는 선택 기능이며,
사용하면 선택한 자료가 설정한 제공자에게 전달될 수 있습니다. API 키와 실제 문서 전체를 이슈에 올리지 마세요.
