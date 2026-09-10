# 변경 기록

이 파일은 공개 릴리스에서 사용자가 확인할 수 있는 변화만 기록합니다.

## [Unreleased]

- 다음 공개 알파에서 확인할 설치·사용 피드백을 수집 중입니다.

## [preview-20260910-logo1] — 2026-09-10

- 사용자 제공 로고를 앱 상단·갤럭시 중앙·메뉴 막대·앱 아이콘에 적용했습니다.
- 앱 번들 버전은 1.0.3이며 설치기와 Homebrew가 새 릴리스를 받습니다.

## [preview-20260910] — 2026-09-10

### 추가

- Markdown 폴더를 연결해 탐색·검색·편집하는 Clonie 공개 알파
- 동봉 임베딩 모델을 포함한 Apple Silicon용 릴리스 ZIP
- Homebrew Cask 설치 경로
- Homebrew가 없는 사용자를 위한 SHA-256 검증 설치기 경로
- 앱 내 음성 연습과 Apple 음성 모델 준비 경로

### 알려진 한계

- macOS 26 이상 Apple Silicon만 지원합니다. Windows와 Intel Mac은 지원하지 않습니다.
- 앱 번들 파일 이름은 아직 `Ghostbar.app`입니다.
- Qwen은 아직 앱에 연결하지 않았습니다.
- 같은 Mac의 격리된 Homebrew 설치는 tap 등록, 릴리스 SHA-256, 설치한 실행 파일 SHA와 codesign까지
  확인했습니다. 앱 실행, Gatekeeper·개발자 신뢰 설정, TCC·음성 권한과 다른 Mac의 첫 설치는 아직
  검증하지 않았습니다.
- Gatekeeper의 **확인 없이 열기**, 마이크·화면 기록 권한과 음성 모델 준비는 사용자가 직접 승인해야 합니다.
- 검색 관련도와 음성 흐름은 공개 알파에서 계속 확인 중입니다.

[Unreleased]: https://github.com/qoal1201/clonie-preview/compare/preview-20260910...main
