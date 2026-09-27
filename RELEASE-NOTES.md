# Clonie 1.1.0 · 같은 자료를 앱과 AI에서 이어 쓰기

Markdown 폴더를 Clonie에 연결하고, 쓰던 AI에서도 같은 자료를 찾아 활용할 수 있습니다.
AI가 보낸 문서 변경은 앱에서 내용을 비교하고 승인한 뒤 저장합니다.

**[Mac용 다운로드](https://github.com/qoal1201/clonie-preview/releases/download/v1.1.0/Clonie-1.1.0-arm64-notarized.zip)** · [설치와 업데이트](INSTALL.md) · [플러그인 안내](plugins/clonie/README.md)

macOS 26 이상 · Apple Silicon(M 시리즈)용입니다. 기본 검색·편집에는 AI 계정이나 API 키가 필요하지 않습니다.

## 달라진 점

- 앱에 MCP와 Clonie 플러그인 0.2.0, 설치기를 함께 넣었습니다.
- 로컬 Codex·Work locally·Codex CLI가 앱에서 고른 저장소를 사용합니다. AI 대화의 프로젝트 폴더는 달라도 됩니다.
- 외부 AI의 문서 변경을 제안으로 받고, **변경** 탭에서 비교·수정·승인한 내용만 원문에 저장합니다.
- 터미널용 Codex CLI를 따로 설치하지 않아도 데스크톱 앱에 포함된 실행 파일로 플러그인을 설치할 수 있습니다.
- 파일·기록·변경 탭의 탐색과 문서 편집 흐름을 보완했습니다.

## 업데이트

Clonie를 정상 종료한 뒤 새 앱으로 교체하세요. 연결한 자료 폴더와 `.clonie`는 그대로 둡니다.
플러그인을 사용한다면 앱을 한 번 연 다음 동봉된 설치 명령을 다시 실행하고, 새 AI 대화에서 연결을 확인하세요.

```bash
/bin/bash /Applications/Clonie.app/Contents/Resources/CloniePlugin/install.sh codex
```

다른 위치에 설치했다면 앱 경로를 바꿉니다. 자세한 순서는 [설치 안내](INSTALL.md#업데이트)에 있습니다.

## 지원 환경

로컬 Codex·Work locally·Codex CLI의 문서 조회·제안·앱 승인·재조회를 확인했습니다.
일반 ChatGPT Chat·원격 Work는 이 로컬 플러그인의 지원 대상이 아닙니다.
Claude Code·Cowork의 실제 계정 사용 검증과 공식 플러그인 목록 등재는 남아 있습니다.

[전체 지원 범위와 문제 해결](INSTALL.md#지원-범위)을 확인하세요.

<details>
<summary>설치 파일과 검증 정보</summary>

이 설치 파일은 Developer ID 서명·Apple 공증·Gatekeeper 검사와 ZIP 재검증을 통과했습니다.
Swift 검사 453개에서 실패가 없었고, 플러그인 검사 20개와 설치기 검사 4개를 통과했습니다.
Swift 검사의 Keychain·OCR 실측 2개는 별도 실행 항목으로 생략했습니다.
같은 Mac의 빈 설치 폴더에서 검증했으며, 새 Mac 첫 실행과 실제 음성 품질을 검증했다는 뜻은 아닙니다.

파일: `Clonie-1.1.0-arm64-notarized.zip`
SHA-256: `10f8b0ef6e9b8c41be6cfc4d90e834a07f74a584127af05a4ce98dd5dd5b2329`

[라이선스](LICENSING.md) · [1.0.6 변경 내역](RELEASE-NOTES-1.0.6.md) · [1.0.5 변경 내역](RELEASE-NOTES-1.0.5.md)

</details>
