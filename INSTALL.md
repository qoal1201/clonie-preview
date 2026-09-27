# 설치와 사용

## Mac 앱 설치

1. [Releases](https://github.com/qoal1201/clonie-preview/releases)에서 Mac용 ZIP을 받습니다.
2. 압축을 풀고 `Clonie.app`을 **응용 프로그램** 폴더로 옮깁니다.
3. 앱을 열고 사용할 Markdown 폴더를 선택합니다.

GitHub의 `Code → Download ZIP`은 소스 코드입니다. 앱을 사용하려면 Releases의 설치 파일을 받으세요.
직접 편집은 실제 파일에 저장됩니다. 처음에는 [예제 문서](sample-vault/)나 자료의 복사본으로 사용해 볼 수 있습니다.

## 외부 AI 연결

Clonie 1.1.0 이상에는 MCP와 플러그인 설치기가 함께 들어 있습니다.
앱을 한 번 실행하고 자료 폴더를 고른 다음 터미널에서 실행합니다.

```bash
/bin/bash /Applications/Clonie.app/Contents/Resources/CloniePlugin/install.sh codex
```

사용자 응용 프로그램 폴더에 설치했다면 앞의 앱 경로를 `~/Applications/Clonie.app`으로 바꿉니다.
설치기는 PATH의 Codex CLI를 우선 사용하며, 없으면 설치된 ChatGPT/Codex 데스크톱 앱의 실행 파일을 찾습니다.
별도의 Clonie API 키나 서버 설정은 필요하지 않습니다.

1. 새 Codex 또는 **Work locally** 대화에서 Clonie 플러그인을 선택합니다.
2. “Clonie에 연결된 저장소 경로를 확인하고 관련 문서를 하나 찾아 읽어줘”라고 요청합니다.
3. 문서 변경을 요청하면 Clonie의 **변경** 탭에서 제안을 검토하고 승인합니다.
4. 같은 AI에 문서를 다시 읽도록 요청해 저장된 내용을 활용합니다.

AI의 프로젝트 폴더를 Clonie 자료 폴더와 맞출 필요는 없습니다. 프로젝트 없는 Work도 사용할 수 있습니다.
일반 ChatGPT Chat·원격 Work는 이 로컬 플러그인의 지원 대상이 아닙니다.
공식 플러그인 목록에는 아직 등재되지 않았으며, 현재는 앱에 동봉된 설치기를 사용합니다.
Claude Code 설치 구성과 스킬 사용법은 [플러그인 안내](plugins/clonie/README.md)에 있습니다.

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

설치 스크립트는 버전이 고정된 앱의 SHA-256과 서명을 확인하고 `~/Applications/Clonie.app`에 설치합니다.
기존 앱이 있으면 보존한 채 중단하며, 설치 후 자동 실행하지 않습니다. `--app-dir`로 다른 설치 위치를 지정할 수 있습니다.

AI 에이전트에게 맡길 때는 이 저장소 주소와 함께 “Clonie를 내 Mac에 설치하고 처음 폴더 연결까지 안내해 줘”라고 요청하세요.
Mac에 접근할 수 있는 에이전트가 필요하며, macOS 권한 승인은 사용자가 직접 합니다.

## 업데이트

코드·문서는 저장소에서 계속 개선하고, 설치 앱은 Releases에서 버전별로 제공합니다.
앱 버전 번호는 어떤 수정이 포함된 파일인지 구별하기 위한 번호입니다. 이미 배포한 ZIP과 태그는 바꾸지 않습니다.

1. Clonie를 정상 종료합니다.
2. 새 ZIP의 앱으로 기존 앱을 교체합니다. 연결한 자료 폴더와 `.clonie`는 지우지 않습니다.
3. 앱을 한 번 열고 기존 폴더와 문서를 확인합니다.
4. 플러그인을 쓴다면 위 동봉 설치 명령을 다시 실행하고 새 AI 대화에서 연결 경로를 확인합니다.

Homebrew 설치는 `brew update` 후 `brew upgrade --cask qoal1201/clonie-preview/clonie`로 갱신할 수 있습니다.
앱과 플러그인 캐시는 별개입니다. GitHub 소스 갱신만으로 설치된 앱이 자동 업데이트되지는 않습니다.

## 지원 범위

- macOS 26 이상, Apple Silicon Mac용입니다. Intel Mac·Windows와 macOS 27은 검증하지 않았습니다.
- 로컬 Codex·Work locally·Codex CLI에서 조회·변경 제안·앱 승인·재조회를 확인했습니다.
- Claude Code·Cowork에는 설치 구성을 제공하지만 실제 계정 사용 검증은 남아 있습니다.
- PDF·Word 변환 도구와 모델은 첫 사용에 다운로드가 필요할 수 있습니다. 문서별 변환 품질은 다를 수 있습니다.
- 음성은 사용할 때만 시작하고 권한을 요청합니다. 기록 기능과 실제 음성 인식 품질은 별도로 확인 중입니다.
- 갤럭시의 Jev 의미 정렬은 별도 연결이 필요한 기능이며, 일반 사용자용 연결은 아직 제공하지 않습니다. 기본 검색·편집은 로컬로 동작합니다.
- 기기 간 동기화·공유·Clonie Cloud는 현재 제공하지 않습니다.

## 문제 해결

**앱 실행이 차단됩니다.** 다운로드한 버전과 오류 문구를 확인해 주세요. 시스템 전체 보안을 끄거나
파일의 quarantine 속성을 지우는 방식으로 해결하지 마세요. macOS의 최초 실행 확인과 음성 권한은 별개입니다.

**폴더의 연결 버튼이 비활성화됩니다.** 앱을 정상 종료하고 다시 연 뒤 폴더를 다시 선택해 주세요.
현재 확인된 복구 방법이며 원인은 조사 중입니다. 계속 발생하면 macOS 버전과 재현 순서를 알려주세요.

**AI가 다른 폴더를 봅니다.** 앱의 폴더 선택과 AI가 보고한 `vaultPath`를 비교해 주세요.
앱에서 폴더를 바꾼 뒤에는 새 AI 대화에서 Clonie를 선택합니다. 기존 대화의 연결은 시작 때의 폴더를 유지할 수 있습니다.
옛 수동 Clonie MCP 설정이 있다면 새 플러그인과 중복되지 않는지도 확인합니다.

**플러그인이 보이지만 문서를 읽지 못합니다.** Work locally인지, Clonie 앱이 호환 버전인지,
호스트의 도구 접근이 허용됐는지 확인합니다. “Clonie 연결을 확인하고 복구해줘”라고 요청하면
설치된 `clonie-init` 스킬로 진단할 수 있습니다.

**변경을 요청했는데 파일이 그대로입니다.** Clonie의 변경 탭에 승인 대기 제안이 있는지 확인합니다.
제안 접수와 파일 저장은 다르며, 승인 후에 파일에 반영됩니다.

해결되지 않으면 앱 버전·Mac 모델·macOS 버전·기대한 동작·실제 결과를 [Issues](https://github.com/qoal1201/clonie-preview/issues)에 남겨주세요.
API 키나 개인 문서 원문은 첨부하지 않아도 됩니다. 자세한 자료 처리는 [개인정보 안내](PRIVACY.md)를 참고하세요.
