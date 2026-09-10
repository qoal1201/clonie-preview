# Clonie — macOS 공개 알파

내 Markdown 폴더를 연결해 자료를 찾고, 읽고, 고치는 로컬 작업 공간입니다.
기존 폴더 구조를 우주 지도로 보여주고, 질문과 관련된 문서를 찾아줍니다.
음성 연습과 저장 자료를 다시 꺼내보는 기능도 실험 중입니다.

> 개발 중인 프로토타입입니다. 실제 작업에서 얻은 피드백을 모으고 있습니다.

[설치 ZIP 다운로드](https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260910) ·
[사용 피드백 남기기](https://github.com/qoal1201/clonie-preview/issues/new?template=feedback.yml)

## 실행 환경

- macOS 26 이상, Apple Silicon Mac. Intel Mac과 Windows는 이번 설치 파일의 지원 대상이 아닙니다.
- 앱 파일 이름은 아직 `Ghostbar.app`입니다. 제품 이름은 Clonie입니다.
- 기본 탐색·편집·로컬 검색에는 AI 구독이나 API 키가 필요하지 않습니다.
- 모델을 동봉한 앱을 사용하면 Python이나 Xcode를 설치하지 않아도 됩니다.
- 한국어 음성 기능은 앱 설정에서 Apple 음성 모델을 별도로 준비해야 합니다. Qwen은 아직 앱에 연결하지 않았습니다.

## 설치

이 저장소의 **Releases**에서 `Clonie-preview-날짜-arm64.zip`을 받습니다.

1. ZIP을 풀고 `Ghostbar.app`을 응용 프로그램 폴더로 옮깁니다.
2. 앱을 열고 처음에는 시험용 Markdown 폴더를 연결합니다.
3. 검색 색인이 준비되면 파일 탐색과 자료 질문을 사용합니다.

이 알파는 Apple 공증을 완료하지 않았습니다. macOS가 첫 실행을 막으면 다운로드 출처를 확인한 뒤
시스템 설정 → 개인정보 보호 및 보안의 해당 앱 항목에서 **확인 없이 열기 / Open Anyway**를 선택합니다.
시스템 전체 보안 기능을 끄거나 터미널에서 격리 속성을 일괄 제거할 필요는 없습니다.
[Apple의 앱 열기 안내](https://support.apple.com/en-us/102445).

이 경로로도 실행되지 않으면 Mac 모델·macOS 버전·오류 문구를 이슈에 남겨주세요.
다른 Mac의 첫 설치 검증은 아직 완료하지 않았습니다.

## 처음 15분

1. 이미 알고 있는 문서 하나를 파일 탐색으로 찾고, 편집 버튼으로 엽니다.
2. 같은 내용을 질문으로 검색하고 관련 문서가 나오는지 봅니다. 자료에 답이 없는 질문도 넣어봅니다.
3. 시험 문서를 한글로 고친 뒤 저장 표시를 확인하고, 앱을 종료했다 다시 열어봅니다.
4. 시험 파일의 이름 변경·이동·되돌리기를 사용합니다.
5. 음성을 시험하려면 설정에서 모델을 준비하고 필요한 권한을 허용한 뒤 연습 모드를 사용합니다.

원본 파일에 편집과 파일 작업이 반영됩니다. 새 폴더나 복사본에서 시작하는 것을 권합니다.
검색 색과 유사도는 문서와 입력의 관련도를 나타내며 정답 여부나 면접 성적을 뜻하지 않습니다.

## 자료와 외부 AI

Markdown은 연결한 폴더에 남고, 검색 색인과 입력 기록은 폴더 안 `.clonie`에 저장됩니다.
기본 검색·편집과 현재 음성 처리는 기기 안에서 수행합니다.
선택 기능인 외부 AI 자료 정리를 사용하면 선택한 자료가 설정한 API 또는 CLI 제공자에 전달될 수 있으며
해당 계정의 비용·사용량이 적용됩니다. 첫 테스트에서는 외부 AI를 연결하지 않아도 됩니다.

MCP는 외부 AI 도구가 같은 저장소를 읽고 쓰게 하는 별도 연결입니다. 기본 앱 테스트에는 필요하지 않습니다.

## 피드백

Issues에서 **사용 피드백**을 선택해 아래를 적어주세요.

- 하려던 일과 기대한 결과
- 실제 결과와 재현 순서
- 앱 빌드, macOS 버전, Mac 모델
- 가능한 경우 개인정보를 지운 예시나 화면

잘된 사례도 환영합니다. API 키·이력서·실제 문서 전체를 공개 이슈에 올리지 마세요.
버그 수정 후 같은 작업이 나아졌는지 다시 확인하는 방식으로 진행합니다.

## 소스에서 빌드

macOS 26 SDK를 포함한 Xcode 또는 Command Line Tools, Swift 6.1 이상이 필요합니다.

```bash
./scripts/fetch-model.sh
./build.sh --app-only --include-model
open Ghostbar.app
```

첫 모델 준비는 Hugging Face 다운로드와 Python 변환 도구 설치를 포함해 수 GB가 필요할 수 있습니다.
이미 변환한 모델이 있으면 재사용합니다. 앱 빌드 자체는 모델을 다운로드하지 않습니다.
일반 앱에는 `GHOSTBAR_QA_SESSION`이나 전용 QA 런처가 필요하지 않습니다.

```bash
GHOSTBAR_REQUIRE_EMBEDDING_MODEL=1 swift test
```

## 현재 한계와 출처

프로토타입입니다. 검색 오탐, 한글 입력, 실제 음성, 다른 Mac의 첫 설치를 계속 확인하고 있습니다.
화면 공유 중 노출 여부는 사용 중인 회의 도구와 OS에서 직접 확인해야 하며 모든 조합을 보장하지 않습니다.
자료 참조나 보조 프로그램이 금지된 평가에는 사용하지 마세요.

이 앱은 [rbc33/Ghostbar](https://github.com/rbc33/Ghostbar)에서 출발했습니다.
Clonie에서 Markdown 저장소·검색·편집·연습·MCP와 관련 검증을 추가했습니다.
임베딩 모델은 [dragonkue/multilingual-e5-small-ko-v2](https://huggingface.co/dragonkue/multilingual-e5-small-ko-v2)를
CoreML로 변환해 사용합니다. 의존성의 원문 고지는 `ThirdPartyNotices/`에 보존합니다.

Clonie의 변경분은 [MIT](LICENSE)로 공개합니다. 상류 README도 MIT를 표시합니다.
상류의 별도 라이선스 파일 부재와 기준 리비전은 [UPSTREAM.md](UPSTREAM.md)에 기록했습니다.
다른 라이선스가 적용되는 모델·의존성·아이콘에는 각각 보존한 고지가 적용됩니다.
