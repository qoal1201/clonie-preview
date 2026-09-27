# Clonie

<img src="assets/branding/ClonieDock.png" width="88" alt="Clonie 로고">

**나만의 맥락 저장소로 가꿉니다.**

흩어진 생각과 자료를 내 저장소에 쌓고, 필요한 순간 나와 AI가 함께 꺼내 씁니다.
Clonie는 내 Markdown 폴더를 연결해 자료를 찾고, 읽고, 고치는 macOS 앱입니다.

**[Mac용 다운로드](https://github.com/qoal1201/clonie-preview/releases)** · [설치 안내](INSTALL.md) · [플러그인](plugins/clonie/README.md) · [변경 기록](CHANGELOG.md)

macOS 26 이상 · Apple Silicon(M 시리즈). 기본 검색·편집에는 AI 계정이나 API 키가 필요하지 않습니다.

## 내 자료를 연결하고, 쓰면서 가꾸기

1. **연결하기** — 쓰고 있는 Markdown 폴더를 그대로 연결합니다.
2. **찾고 읽기** — 질문으로 관련 문서와 근거 문단을 찾고, 같은 화면에서 읽습니다.
3. **보완하기** — 문서를 직접 편집하거나 외부 AI에 보완을 요청합니다.
4. **다시 꺼내 쓰기** — 저장한 내용을 다음 작업에서 찾아 활용합니다.

```mermaid
flowchart LR
  A[내 Markdown 폴더] --> B[찾고 읽기]
  B --> C[작업에 활용]
  C --> D[문서 보완]
  D --> B
```

앱에서 직접 편집하면 연결한 Markdown에 저장됩니다. PDF·Word 자료는 원본을 보존하며 가져올 수 있습니다.
파일·기록·변경 탭에서 자료와 작업 내용을 함께 살펴봅니다.

## 쓰던 AI에서도 같은 자료 사용하기

Clonie 플러그인을 설치하면 로컬 Codex·Work locally·Codex CLI에서 같은 저장소를 읽고 활용할 수 있습니다.
AI 대화의 프로젝트와 Clonie에 연결한 폴더가 같을 필요는 없습니다. 프로젝트 없이 시작한 Work에서도 사용할 수 있습니다.

> Clonie에서 이번 작업과 관련된 기록을 찾아 읽어줘. 참고한 문서 경로도 알려줘.

문서를 바꾸고 싶다면 변경 제안을 요청합니다.

> 이 문서에 오늘 결정한 내용을 반영하는 변경 제안을 보내줘.

AI의 제안은 Clonie의 **변경** 탭에서 비교·수정·승인합니다. 승인한 내용만 Markdown에 저장되며,
AI도 다음 조회에서 저장된 내용을 읽습니다. [플러그인 설치와 지원 환경](plugins/clonie/README.md)을 확인하세요.

## 처음 사용하기

1. [Releases](https://github.com/qoal1201/clonie-preview/releases)에서 Mac용 ZIP을 받습니다.
2. 압축을 풀고 `Clonie.app`을 응용 프로그램 폴더로 옮긴 뒤 실행합니다.
3. 사용할 Markdown 폴더를 선택합니다. 가볍게 시작하려면 이 저장소의 [예제 문서](sample-vault/)를 사용할 수 있습니다.
4. 자료에 질문하고 문서를 열어 조금 고친 뒤 다시 찾아보세요.
5. 외부 AI에서도 자료를 쓰려면 [Clonie 플러그인](plugins/clonie/README.md)을 설치합니다.

[Homebrew·터미널 설치](INSTALL.md#터미널에서-설치) · [업데이트](INSTALL.md#업데이트) · [문제 해결](INSTALL.md#문제-해결)

## 내 자료와 개인정보

Markdown과 검색 색인·기록은 사용자가 연결한 폴더에 보관합니다. 앱을 지워도 자료 폴더는 유지됩니다.
기본 검색은 기기 안에서 처리합니다. 외부 AI에 자료를 읽도록 요청하면 해당 내용은 그 AI 서비스에 전달됩니다.

[개인정보 안내](PRIVACY.md) · [지원 범위](INSTALL.md#지원-범위)

## 참여하기

[사용 피드백](https://github.com/qoal1201/clonie-preview/issues/new?template=feedback.yml)에
하려던 일·기대한 결과·실제 결과를 알려주세요. 코드와 문서 개선은 [기여 안내](CONTRIBUTING.md)를 참고하세요.
보안 문제는 [비공개 제보](SECURITY.md)로 받습니다.

## 라이선스

신규 자체 변경에는 [PolyForm Perimeter 1.0.1](LICENSE)을 적용합니다. 사용 제한이 있는 소스 공개 라이선스입니다.
기존 MIT 권리와 제3자 고지는 유지합니다. [적용 범위](LICENSING.md) · [제3자 고지](ThirdPartyNotices/) · [프로젝트 출처](HISTORY.md)
