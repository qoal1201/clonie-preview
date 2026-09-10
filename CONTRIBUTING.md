# 기여 안내

Clonie는 공개 알파입니다. 작은 코드·문서 수정, 재현 가능한 버그 제보, 사용성 피드백을 환영합니다.
방향이 큰 변경은 먼저 [Issue](https://github.com/qoal1201/clonie-preview/issues)에서 문제와 제안을
나눠 주세요.

## 시작하기

1. 현재 Issue와 README의 지원 범위를 확인합니다.
2. macOS 26 이상 Apple Silicon 환경에서 문제를 재현합니다.
3. 한 Pull Request에는 한 가지 목적만 담고, 변경 이유와 재현·확인 방법을 적습니다.
4. 화면 문구나 동작을 바꾸면 사용자가 따라 할 수 있는 전후 절차를 함께 적습니다.

작은 수정은 기존 구조와 파일 분류를 따릅니다. 새 의존성이나 공개 API를 추가하기 전에 Issue에서
그 필요성과 유지 비용을 설명해 주세요.

## 자료와 비밀정보

개인 Markdown, 이력서, 음성 기록, API 키, 계정 정보, 사내 문서와 개인 경로는 커밋하지 않습니다.
재현 자료가 필요하면 `sample-vault`처럼 공개 가능한 최소 예시를 만들고, 원본의 이름·내용·식별자를
지운 뒤 올립니다. 실제 사용자 자료나 외부 서비스 응답을 저장소에 업로드하지 마세요.

## 테스트

Swift 테스트는 macOS 26 SDK와 Swift 6.1 이상이 필요합니다.

```bash
swift test
```

변경 범위가 분명하면 관련 타깃만 먼저 확인할 수 있습니다.

```bash
swift test --filter ClonieCoreTests
swift test --filter ClonieDocumentsTests
swift test --filter ClonieIndexTests
swift test --filter ClonieCloudTests
swift test --filter ClonieMCPTests
```

임베딩 점수 일치 검사는 모델 산출물이 준비된 환경에서 실행합니다.

```bash
CLONIE_REQUIRE_EMBEDDING_MODEL=1 swift test --filter ClonieEmbeddingTests
```

모델이 없다면 먼저 `./scripts/fetch-model.sh`로 준비할 수 있습니다. 이 단계는 외부 다운로드와
변환 도구 설치를 포함할 수 있습니다. 공개 릴리스 사용자는 동봉 모델이 있는 앱을 사용하므로 이 준비가
필수는 아닙니다.

설치기를 바꾼 경우에는 앱을 실행하지 않는 회귀 검사를 별도로 확인합니다.

```bash
python3 scripts/test-install.py
```

실제 릴리스 ZIP을 사용한 설치 검증은 별도 임시 디렉터리에서 수행하며, Gatekeeper 승인·개발자 신뢰
설정·TCC·음성 권한과 다른 Mac의 첫 실행을 자동 테스트의 성공으로 기록하지 않습니다.

화면 검증 자료와 개발용 원본 검사는 개발 저장소의 별도 범위입니다. 이 공개 저장소에는 CI 상태 배지를
두지 않으며, 배지나 로컬 결과를 공개 CI의 성공으로 표현하지 않습니다. Pull Request에는 실제로 실행한
명령과 생략한 검사를 구분해 적어 주세요.

## Pull Request

제목과 본문에 다음을 간단히 적습니다.

- 어떤 사용자 문제를 해결하는가
- 재현 단계와 기대·실제 결과
- 어떤 파일을 바꿨는가
- 실행한 테스트와 실행하지 못한 테스트
- 개인정보나 외부 서비스 접근이 필요한지

기능 수정은 가능하면 실패하던 재현 사례를 검증에 포함합니다. 문서 수정은 사용자가 그대로 따라 할
수 있는 명령과 지원 범위를 확인합니다. 릴리스 파일, Homebrew 배포, 라이선스와 외부 공개 범위를
바꾸는 변경은 먼저 Issue에서 논의해 주세요.

## 라이선스

기여물은 프로젝트의 [MIT License](LICENSE)를 따릅니다. 포함된 제3자 구성요소의 출처·고지는
[ThirdPartyNotices/](ThirdPartyNotices/)에 보존합니다. 이전 버전의 출처는 [개발 이력](HISTORY.md)에 있습니다.
