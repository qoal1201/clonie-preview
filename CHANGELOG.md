# 변경 기록

배포 파일과 상세 릴리스 노트는 [GitHub Releases](https://github.com/qoal1201/clonie-preview/releases)에서 확인할 수 있습니다.

## [Unreleased]

- 설치·업데이트·플러그인 안내를 정리했습니다.

## [1.1.0] — 2026-09-28

- Clonie 앱에 Codex·Claude Code용 플러그인과 설치기를 동봉합니다.
- 외부 AI의 문서 변경을 승인 대기 제안으로 받고, Clonie 변경 탭에서 승인한 내용만 저장합니다.
- 프로젝트 없는 Work locally와 다른 작업 폴더의 Codex에서도 앱이 선택한 저장소를 사용합니다.
- 터미널용 Codex CLI가 없어도 설치된 ChatGPT/Codex 데스크톱의 실행 파일로 플러그인을 설치합니다.
- 저장소 탐색·검색·문서 편집과 파일·기록·변경 탭의 흐름을 보완합니다.

## [1.0.6] — 2026-09-19

- Developer ID 서명·Apple 공증과 배포 앱 번들 구성을 수정했습니다.
- 다른 제품의 설정·모델·자료 자동 이관을 제거했습니다.
- 단축키 설정의 특수문자 전달과 잘못된 설정값 처리를 보완했습니다.

## [1.0.5] — 2026-09-17

- Markdown 편집·문서 가져오기·대화 기록·MCP 변경 확인을 보완했습니다.
- 기록을 한 번 누르면 본문을 바로 열고, 마이크 단독 질문도 저장소 검색과 기록에 연결합니다.
- 사용 시작에서 준비된 권한·모델은 숨기고 범위·입력 선택을 저장소별로 기억합니다.
- 신규 자체 변경에 PolyForm Perimeter 1.0.1을 적용했습니다. 기존 MIT 및 제3자 권리는 유지합니다.

## [1.0.4] — 2026-09-10

- 앱·실행 파일·패키지 이름을 Clonie로 통일했습니다.
- 당시 기존 설치의 설정과 로컬 모델을 이어 읽는 경로를 추가했습니다. 이 동작은 1.0.6에서 제거했습니다.
- 사용하지 않던 채팅·Whisper 녹음·캡처·스트리밍 코드와 캡처 단축키 설정을 제거했습니다.
- 앱 진입점, 창, 전역 단축키, 백엔드 설정, 모델 목록 조회와 패키징을 다시 구현했습니다.

## [1.0.3] — 2026-09-10

- Clonie 로고를 앱 화면·메뉴 막대·앱 아이콘에 적용했습니다.

## [첫 공개] — 2026-09-10

- Markdown 폴더 탐색·검색·편집과 Apple Silicon용 앱을 공개했습니다.
- 임베딩 모델을 앱에 동봉하고, Homebrew Cask와 SHA-256 검증 설치기를 제공했습니다.
- 앱 내 음성 연습과 Apple 음성 모델 준비 경로를 추가했습니다.

[Unreleased]: https://github.com/qoal1201/clonie-preview/compare/v1.1.0...main
[1.1.0]: https://github.com/qoal1201/clonie-preview/releases/tag/v1.1.0
[1.0.6]: https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260919-clonie1
[1.0.5]: https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260917-clonie1
[1.0.4]: https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260910-clonie1
[1.0.3]: https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260910-logo1
[첫 공개]: https://github.com/qoal1201/clonie-preview/releases/tag/preview-20260910
