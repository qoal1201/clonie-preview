# Clonie

Clonie는 **내 Markdown 폴더를 연결해 찾고, 읽고, 고치는 macOS 로컬 작업 공간**입니다.
현재는 공개 알파(preview)이며, 검색·편집·음성 연습 흐름을 실제 사용자 환경에서 확인하고 있습니다.

## 빠른 설치

지원 환경은 **macOS 26 이상, Apple Silicon Mac**입니다. 설치 뒤 앱이 자동으로 실행되지는 않습니다.

Homebrew를 사용한다면 다음 명령을 실행합니다.

```bash
brew tap qoal1201/clonie-preview https://github.com/qoal1201/clonie-preview
brew install --cask qoal1201/clonie-preview/clonie
```

Homebrew가 없다면 공개 저장소의 최신 설치 스크립트를 내려받아 실행할 수 있습니다.

```bash
curl -fL https://raw.githubusercontent.com/qoal1201/clonie-preview/main/scripts/install.sh -o /tmp/clonie-install.sh
bash /tmp/clonie-install.sh
```

이 설치기는 동봉 모델이 포함된 릴리스 앱의 SHA-256을 확인하고, 기본적으로
`~/Applications/Ghostbar.app`에 설치합니다. 같은 이름의 기존 앱을 덮어쓰지 않으며,
설치가 끝난 뒤 앱을 자동으로 열지 않습니다.

AI 에이전트에게 설치를 맡기려면 저장소 주소와 함께 다음처럼 요청하면 됩니다.

> https://github.com/qoal1201/clonie-preview 의 README와 AGENTS.md를 읽고,
> 내 Mac의 지원 여부와 기존 설치를 확인한 뒤 Clonie를 설치하고 실행해 줘.
> 처음 쓸 수 있도록 폴더 연결까지 안내하고, 내가 직접 승인해야 하는 단계는 알려 줘.

에이전트용 절차는 [AGENTS.md](AGENTS.md), 설치 위치·첫 실행·문제 해결은
[INSTALL.md](INSTALL.md)에 있습니다.

설치 스크립트나 Homebrew를 쓰지 않으려면 [preview-20260910 릴리스](https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260910)에서
Apple Silicon용 ZIP을 내려받아 압축을 풀고 `Ghostbar.app`을 응용 프로그램 폴더로 옮기면 됩니다.

첫 실행 때 macOS가 앱을 막으면 시스템 설정의 개인정보 보호 및 보안에서 해당 앱을 확인한 뒤
**확인 없이 열기(Open Anyway)**를 직접 승인해야 합니다. 음성 연습을 사용할 때도 마이크·화면 기록
권한과 Apple 음성 모델 준비를 사람이 승인해야 합니다. Qwen은 아직 앱에 연결하지 않았습니다.

## 사용법

1. `Ghostbar.app`을 열고 Markdown 폴더를 연결합니다. 처음에는 `sample-vault`나 복사해 둔 시험용 폴더를 권합니다.
2. 파일 탐색에서 문서를 열고 편집한 뒤 저장 표시를 확인합니다.
3. 같은 자료를 질문으로 검색하고, 답이 없는 질문도 넣어 검색 경계를 확인합니다.
4. 필요하면 파일 이름 변경·이동·되돌리기를 시험합니다.
5. 음성 연습은 설정에서 필요한 권한과 Apple 음성 모델을 준비한 뒤 사용합니다.

앱 파일 이름은 현재도 `Ghostbar.app`입니다. Clonie의 새 앱 번들 이름은 아직 정하지 않았습니다.
원본 파일과 `.clonie` 검색 색인·입력 기록을 직접 다루므로 중요한 자료는 복사본으로 먼저 시험하세요.

## 개인정보와 외부 연결

기본 검색·편집과 현재의 음성 처리는 기기 안에서 수행합니다. Markdown은 연결한 폴더에 남고,
검색 색인과 입력 기록은 그 폴더의 `.clonie`에 저장됩니다.

외부 AI 자료 정리는 선택 기능입니다. 사용하면 선택한 자료가 설정한 API 또는 CLI 제공자에게
전달될 수 있고, 해당 계정의 비용과 사용량이 적용됩니다. MCP도 별도 선택 연결이며 기본 앱 사용에는
필요하지 않습니다.

실제 문서, 이력서, API 키, 계정 정보는 공개 이슈나 Pull Request에 올리지 마세요.

## 피드백과 버그 제보

[Issues](https://github.com/qoal1201/clonie-preview/issues)에서 사용 피드백 또는 버그 제보를 선택해 주세요.
다음 정보를 함께 적으면 재현에 도움이 됩니다.

- 하려던 일과 기대한 결과
- 실제 결과와 재현 순서
- Mac 모델과 macOS 버전
- 가능한 경우 개인정보를 지운 예시와 오류 문구

같은 Mac의 격리된 Homebrew 설치는 tap 등록, 릴리스 다운로드·SHA-256 확인, 별도 디렉터리 설치,
설치한 실행 파일 SHA와 codesign 확인까지 통과했습니다. 이 검증에서는 앱을 실행하지 않았으므로
Gatekeeper 승인, 개발자 신뢰 설정, TCC와 음성 권한은 아직 확인하지 않았습니다. 다른 Mac의 첫 설치도
아직 검증하지 않았습니다. Windows와 Intel Mac은 지원하지 않습니다.

보안 취약점은 공개 이슈 대신 [SECURITY.md](SECURITY.md)의 절차를 사용해 주세요.

## 소스에서 빌드

개발자는 macOS 26 SDK를 포함한 Xcode 또는 Command Line Tools와 Swift 6.1 이상을 사용합니다.
앱을 직접 빌드할 때 모델을 선택적으로 동봉할 수 있습니다.

```bash
./scripts/fetch-model.sh
./build.sh --app-only --include-model
open Ghostbar.app
```

모델을 처음 준비할 때는 외부 다운로드와 변환 도구 설치로 수 GB가 필요할 수 있습니다.
기본 앱 빌드는 모델을 자동으로 내려받지 않습니다. 기여자가 확인할 테스트 범위는
[CONTRIBUTING.md](CONTRIBUTING.md)에 적었습니다.

## 현재 한계

- 공개 알파라서 검색 오탐, 한글 입력, 음성 흐름, 파일 변경 동기화를 계속 확인하고 있습니다.
- macOS 26 이상 Apple Silicon만 지원합니다. Windows와 Intel Mac은 지원하지 않습니다.
- 같은 Mac의 격리 Homebrew 설치는 설치 산출물까지 확인했지만 앱 실행, Gatekeeper·개발자 신뢰 설정,
  TCC와 음성 권한은 검증하지 않았습니다. 다른 Mac의 첫 설치는 아직 검증되지 않았습니다.
- 화면 공유 중 노출 여부는 회의 도구와 OS 조합별로 직접 확인해야 하며 모든 조합을 보장하지 않습니다.
- 검색 색과 유사도는 관련도를 나타내며 정답이나 면접 성적을 보장하지 않습니다.
- 자료 참조나 보조 프로그램이 금지된 평가에는 사용하지 마세요.

## 기여

작은 수정, 재현 가능한 버그 제보, 문서 개선을 환영합니다. 공개 자료의 범위와 테스트 방법은
[CONTRIBUTING.md](CONTRIBUTING.md)를 먼저 읽어 주세요.

## 라이선스와 출처

Clonie의 변경분은 [MIT License](LICENSE)로 배포합니다. 프로젝트는
[rbc33/Ghostbar](https://github.com/rbc33/Ghostbar)에서 출발했으며, 상류 README에 표시된 MIT
고지와 상류 저장소 루트에 별도 LICENSE 파일이 없었던 사실은 [UPSTREAM.md](UPSTREAM.md)에 보존했습니다.
모델·아이콘·Swift 의존성의 원문 고지는 [ThirdPartyNotices/](ThirdPartyNotices/)에 있습니다.
