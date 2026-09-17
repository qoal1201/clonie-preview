# 기여 안내

Clonie의 공개 소스, 설치 파일, 사용 피드백을 이 저장소에서 관리합니다.
작은 코드·문서 수정과 재현 가능한 버그 제보를 환영합니다. 큰 기능 변경은 먼저 Issue로 문제와 제안을 나눠 주세요.

## 문제를 알리거나 수정하려면

1. 기존 Issues와 현재 지원 환경을 확인합니다.
2. 앱 버전·재현 순서·기대한 결과·실제 결과를 적습니다.
3. 직접 수정한다면 한 PR에 한 가지 목적을 담고, 실행한 검사와 확인하지 못한 내용을 구분합니다.

외부 제보는 이 저장소에서 해결 상태와 반영 버전을 안내합니다.
기여를 반영할 때 저자와 출처를 보존합니다. 개인 자료, 계정 정보, API 키는 이슈·PR·첨부물에 넣지 마세요.
보안 문제는 [SECURITY.md](SECURITY.md)의 비공개 경로로 제보해 주세요.

## 소스에서 빌드

Apple Silicon Mac, macOS 26 SDK가 포함된 Xcode 또는 Command Line Tools와 Swift 6.1 이상이 필요합니다.
앱 사용만 원하는 경우에는 README의 [배포 앱 설치](INSTALL.md)를 이용하세요.

```bash
./scripts/fetch-model.sh
./build.sh --app-only --include-model
open Clonie.app
```

첫 모델 준비에는 외부 다운로드와 변환 도구 설치로 수 GB가 필요할 수 있습니다.
앱 빌드는 로컬 서명 설정을 사용합니다. 여러 인증서가 있다면 `CLONIE_SIGN_ID`로 지정할 수 있습니다.
이 개발 빌드가 Apple 공증을 받은 배포판이 되는 것은 아닙니다.

## 검사

```bash
swift test
python3 scripts/test-install.py
python3 scripts/check-public-repo.py --root .
```

특정 기능만 수정했다면 관련 Swift 타깃을 먼저 검사할 수 있습니다.
모델을 사용하는 임베딩 검사는 `./scripts/fetch-model.sh`로 준비한 뒤 다음과 같이 실행합니다.

```bash
CLONIE_REQUIRE_EMBEDDING_MODEL=1 swift test --filter ClonieEmbeddingTests
```

공개 CI는 문서 링크·민감한 파일명·내부 문구와 비밀정보 패턴을 검사합니다.
앱 실행·실제 음성·다른 Mac 설치를 검증하는 CI는 아닙니다. PR에는 실제로 수행한 검사를 적어 주세요.

## 릴리스와 문서

기능이 바뀌면 사용법·지원 범위·알려진 문제·CHANGELOG도 함께 확인합니다. 화면이 달라졌다면 README 이미지가 맞는지 검토합니다.
앱 릴리스에서는 다운로드 버전·URL·SHA-256을 설치기와 Cask에 함께 반영합니다. 이미 공개한 파일과 태그는 바꾸지 않습니다.

소스의 커밋, 사용자용 변경 기록, 공개 릴리스를 통해 개선 과정을 확인할 수 있도록 유지합니다.
테스트 숫자만으로 검색 정확도나 실사용 효과를 주장하지 않습니다.

## 라이선스

신규 자체 코드의 기여물은 [PolyForm Perimeter 1.0.1](LICENSE)을 따릅니다.
권한이 없는 코드를 제출하지 말고, 제3자 코드는 원래 출처·라이선스·고지를 보존하세요.
기존 MIT 권리와 적용 범위는 [LICENSING.md](LICENSING.md), 프로젝트의 출처는 [HISTORY.md](HISTORY.md)를 따릅니다.
