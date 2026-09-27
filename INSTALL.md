# 설치와 사용

## Mac 앱 설치

macOS 26 이상, Apple Silicon(M 시리즈) Mac이 필요합니다.

1. [최신 릴리스](https://github.com/qoal1201/clonie-preview/releases/latest)에서 Mac용 ZIP을 받습니다.
2. 압축을 풀고 `Clonie.app`을 **응용 프로그램** 폴더로 옮깁니다.
3. 앱을 열고 사용할 Markdown 폴더를 선택합니다.

현재 배포 앱은 Developer ID 서명과 Apple 공증을 거쳤습니다.
GitHub의 `Code → Download ZIP`은 소스 코드입니다. 앱을 사용하려면 릴리스의 설치 파일을 받으세요.
직접 편집은 실제 파일에 저장됩니다. 처음에는 [예제 문서](sample-vault/)나 자료의 복사본으로 사용해 볼 수 있습니다.

## 터미널에서 설치

Homebrew를 사용한다면:

```bash
brew tap qoal1201/clonie-preview https://github.com/qoal1201/clonie-preview
brew install --cask qoal1201/clonie-preview/clonie
```

Homebrew 없이 설치하려면:

```bash
clonie_install_dir="$(mktemp -d)"
curl --fail --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/qoal1201/clonie-preview/main/scripts/install.sh \
  -o "$clonie_install_dir/install.sh" && bash "$clonie_install_dir/install.sh"
```

설치 스크립트는 앱의 SHA-256과 서명을 확인하고 `~/Applications/Clonie.app`에 설치합니다.
기존 앱이 있으면 보존한 채 중단하며, 설치 후 자동 실행하지 않습니다. `--app-dir`로 다른 설치 위치를 지정할 수 있습니다.

Mac에 접근할 수 있는 AI 에이전트에게 저장소 주소와 함께 “Clonie를 설치하고 처음 폴더 연결까지 안내해 줘”라고
요청할 수도 있습니다. macOS 권한 승인은 사용자가 직접 합니다.

## 외부 AI 연결

Clonie 앱을 한 번 실행하고 자료 폴더를 고른 뒤 [플러그인 설치 안내](plugins/clonie/README.md#설치)를 따르세요.
앱에 MCP와 설치기가 포함되어 있으며, 별도의 Clonie 계정·API 키·서버 설정은 필요하지 않습니다.

로컬 Codex·Work locally·Codex CLI에서 연결할 수 있습니다. 지원 환경과 사용 예시는
[플러그인 안내](plugins/clonie/README.md#지원-환경)에 있습니다.

## 업데이트

1. Clonie를 정상 종료합니다.
2. [최신 릴리스](https://github.com/qoal1201/clonie-preview/releases/latest)의 앱으로 기존 앱을 교체합니다.
   연결한 자료 폴더와 `.clonie`는 그대로 둡니다.
3. 앱을 한 번 열고 기존 폴더와 문서를 확인합니다.
4. 외부 AI를 쓴다면 [플러그인도 업데이트](plugins/clonie/README.md#업데이트)합니다.

Homebrew로 설치했다면 앱을 종료한 뒤 다음 명령으로 갱신하고, 위 3·4단계를 진행합니다.

```bash
brew update
brew upgrade --cask qoal1201/clonie-preview/clonie
```

GitHub의 소스 변경은 설치된 앱과 플러그인에 자동 반영되지 않습니다.

## 지원 범위

- 배포 앱은 Apple Silicon용입니다. 실제 동작은 macOS 26에서 확인했으며 macOS 27은 아직 검증하지 않았습니다.
- 외부 AI별 지원 여부는 [플러그인의 지원 환경](plugins/clonie/README.md#지원-환경)을 확인하세요.
- PDF·Word 변환 도구와 모델은 첫 사용에 다운로드가 필요할 수 있습니다. 문서별 변환 품질은 다를 수 있습니다.
- 음성은 사용할 때만 시작하고 권한을 요청합니다. 실제 음성 인식 품질은 확인 중입니다.
- 갤럭시의 Jev 의미 정렬은 별도 연결이 필요하며, 일반 사용자용 연결은 아직 제공하지 않습니다. 기본 검색·편집은 로컬로 동작합니다.
- 기기 간 동기화·공유·Clonie Cloud는 현재 제공하지 않습니다.

## 문제 해결

**앱 실행이 차단됩니다.** 최신 릴리스의 설치 파일인지 확인하고, 다운로드한 버전과 오류 문구를 알려주세요.
macOS의 최초 실행 확인과 음성 권한은 별개입니다. 시스템 전체 보안을 끄거나 quarantine 속성을 삭제할 필요는 없습니다.

**폴더의 연결 버튼이 비활성화됩니다.** 앱을 정상 종료하고 다시 연 뒤 폴더를 다시 선택해 주세요.
현재 확인된 복구 방법이며 원인은 조사 중입니다. 계속 발생하면 macOS 버전과 재현 순서를 알려주세요.

**AI가 문서를 읽지 못하거나 다른 폴더를 봅니다.** [플러그인 문제 해결](plugins/clonie/README.md#문제-해결)을 참고하세요.

**변경을 요청했는데 파일이 그대로입니다.** Clonie의 **변경** 탭에 승인 대기 제안이 있는지 확인하세요.
승인한 내용이 원문에 저장됩니다.

해결되지 않으면 앱 버전·Mac 모델·macOS 버전과 재현 순서를 [Issues](https://github.com/qoal1201/clonie-preview/issues)에 남겨주세요.
개인 문서 원문이나 API 키 대신 짧은 재현 예시를 사용하세요. 자세한 자료 처리는 [개인정보 안내](PRIVACY.md)를 참고하세요.
