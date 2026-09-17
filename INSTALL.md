# 설치 안내

Clonie 공개 알파는 **macOS 26 이상, Apple Silicon Mac**에서 실행합니다. Windows와 Intel Mac은
지원하지 않습니다. 앱 번들 파일 이름은 `Clonie.app`입니다.

## 권장 설치: Homebrew

Homebrew가 있으면 다음 순서로 설치합니다.

```bash
brew tap qoal1201/clonie-preview https://github.com/qoal1201/clonie-preview
brew install --cask qoal1201/clonie-preview/clonie
```

동봉 모델이 포함된 릴리스 앱을 설치하며, 설치가 끝나도 앱은 자동으로 실행되지 않습니다.
1.0.5는 같은 개발 Mac에서 설치기·체크섬·임시 폴더 설치·서명을 확인했습니다.
이번 버전의 Homebrew 설치 실행, 다른 Mac 첫 설치, Gatekeeper·음성 권한 승인은 아직 별도 검증 전입니다.
[릴리스 노트](RELEASE-NOTES.md)의 확인 범위를 참고하세요.

## Homebrew 없이 설치

공개 저장소의 `main`에 있는 설치 스크립트를 읽을 수 있는 임시 경로에 내려받아 실행합니다.

```bash
curl -fL https://raw.githubusercontent.com/qoal1201/clonie-preview/main/scripts/install.sh -o /tmp/clonie-install.sh
bash /tmp/clonie-install.sh
```

스크립트는 `preview-20260917-clonie1`으로 고정된 동봉 모델 앱과 SHA-256을 확인하고 기본 경로
`~/Applications/Clonie.app`에 설치합니다. 같은 경로에 기존 `Clonie.app` 또는
`Ghostbar.app`이 있으면 기존 앱을 보존한 채 중단합니다. 이전 앱에서 넘어올 때는
`--app-dir`로 별도 폴더를 지정해 두 앱을 비교한 뒤, 기존 앱의 정리는 직접 결정합니다.
설치 후 자동 실행도 하지 않습니다.

## ZIP으로 설치

[preview-20260917-clonie1 릴리스](https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260917-clonie1)에서
Apple Silicon용 ZIP을 내려받아 압축을 풉니다. `Clonie.app`을 응용 프로그램 폴더로 옮긴 뒤 엽니다.
릴리스 앱에는 모델이 동봉되어 있어 Python이나 Xcode를 설치하지 않아도 기본 사용을 시작할 수 있습니다.

## 첫 실행

1. `Clonie.app`을 엽니다.
2. macOS가 출처를 확인할 수 없다고 표시하면 시스템 설정 → 개인정보 보호 및 보안에서 앱을 확인하고
   **확인 없이 열기(Open Anyway)**를 직접 승인합니다.
3. 앱에서 Markdown 폴더를 선택합니다. 중요한 자료는 복사본으로 먼저 연결하세요.
4. 자료에 질문해 문서를 찾고, 열어 조금 수정한 뒤 저장 표시를 확인합니다.
5. 음성을 쓸 때만 사용 시작에서 범위와 입력을 고릅니다. 처음에는 마이크와 Apple 음성 모델을 준비하며, 상대 음성을 포함할 때만 시스템 오디오 권한도 필요합니다.
6. 마이크 단독은 내 질문으로, 상대 음성 포함은 상대 질문으로 검색합니다. 설정은 저장소별로 기억하며 이미 허용한 권한은 다시 요구하지 않습니다.

Gatekeeper 승인과 음성 권한·모델 준비는 사용자의 명시적인 선택이 필요한 단계입니다. 설치기는 이 승인들을
대신 수행하지 않습니다.

## AI 에이전트에게 맡기기

이 저장소 링크와 함께 아래 문장을 보내면 됩니다. 링크를 읽는 것만으로 설치가 승인되지는 않습니다.

> 이 Clonie 앱을 내 Mac에 설치하고 실행해 줘. README와 AGENTS.md를 읽고 지원 환경과 기존 설치부터 확인해 줘. 처음 폴더 연결까지 안내해 줘.

에이전트가 터미널·파일 접근 도구를 갖추고 있어야 합니다. 사용자의 Mac에 접근하지 못하는 채팅형 AI는
명령과 절차만 안내할 수 있습니다. 첫 실행 허용과 음성 권한은 사용자가 승인합니다.

## 기존 앱이 있다면

설치기는 기존 앱을 덮어쓰지 않습니다. 새 버전 설치·교체를 요청했다면 먼저 실행 중인 앱을 정상 종료하고,
기존 앱과 연결한 자료를 보존한 채 진행하세요. Bash 설치기는 `--app-dir`로 별도 위치를 선택할 수 있습니다.
Homebrew 설치를 업데이트하려면 기존 설치를 확인한 뒤 `brew update`와
`brew upgrade --cask qoal1201/clonie-preview/clonie`를 사용합니다. 저장소와 `.clonie`를 지우거나 권한을 초기화할 필요는 없습니다.

## 문제가 생겼을 때

- macOS 26 이상인지, Apple Silicon Mac인지 확인합니다.
- 앱 이름이 `Clonie.app`인지 확인합니다.
- Gatekeeper 메시지의 **확인 없이 열기**를 승인했는지 확인합니다.
- 설치 위치에 기존 `Clonie.app` 또는 `Ghostbar.app`이 있으면 설치기는 덮어쓰지 않으므로, 기존 파일을
  보존한 뒤 `--app-dir`로 원하는 별도 설치 경로를 지정해 다시 시도합니다.
- 음성 모델 준비가 계속 실패하면 Clonie를 정상 종료한 뒤 다시 열어 상태를 확인합니다. 실패를 우회해 준비됨으로 간주하지 않습니다.
- 다른 Mac 설치는 아직 검증하지 않았습니다. Mac 모델, macOS 버전, 오류 문구를 [Issues](https://github.com/qoal1201/clonie-preview/issues)에 남겨 주세요.

## 개인정보

Markdown과 `.clonie` 색인·입력 기록은 연결한 폴더에 남습니다. 외부 AI는 MCP로 선택해 연결하며,
AI에 자료를 참고하도록 요청하면 그 도구가 읽은 내용이 해당 AI 서비스에 전달될 수 있습니다.
PDF·Word의 최초 가져오기는 변환 도구·모델 다운로드가 필요할 수 있습니다. API 키와 실제 문서 전체를 이슈에 올리지 마세요.
