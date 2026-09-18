# macOS 공개 배포

개발용 `build.sh`와 외부 배포 검증은 다르다. `codesign --verify`만 통과한 앱을
Gatekeeper 통과로 보고하지 않는다. 공개 ZIP은 아래 절차의 `status: verified` 산출물만 사용한다.
기존 공개 ZIP·태그는 교체하지 않고 새 버전/태그를 만든다.

## 매번 공증해야 하는 범위

로컬 개발 빌드나 일반 커밋, README 수정마다 공증하지 않는다. **변경된 앱을 새 공개 버전으로 제공할 때**
새 서명/공증/검사를 수행한다. 사용자가 같은 파일을 다운로드할 때마다 제출하는 절차가 아니다.
Apple의 자동 검사이며 App Store 심사와는 다르다. 처리 시간을 고정된 분 단위로 약속하지 않는다.
현재는 아래 스크립트로 실행하며 GitHub CI 자동 발행은 아직 구성하지 않았다.
공개 저장소/배포 참고 근거는 개발 레포의 `docs/research/2026-09-17-public-repo-reference.md`에 있다.

## 최초 준비

1. Apple Developer Program 계정의 최신 약관은 계정 소유자가 직접 검토·동의한다.
2. Xcode → Settings → Apple Accounts → 팀 → Manage Certificates에서
   **Developer ID Application** 인증서를 발급한다. Apple Development/Apple Distribution과 다르다.
   기존 개발용 인증서는 유지한다. 인증서·개인 키를 레포에 넣지 않는다.
3. 공증 자격 증명을 사용자의 터미널에서 대화형으로 저장한다.

   ```bash
   xcrun notarytool store-credentials clonie-notary
   ```

   Apple ID·팀 ID·앱 암호 또는 지원되는 App Store Connect API 키를 사용한다.
   비밀번호는 채팅·스크립트·셸 인자·로그에 넣지 않는다. 앱 암호 생성과 입력은 사용자가 직접 한다.
   스크립트는 Keychain 프로필 이름만 받는다.

## 배포

먼저 변경에 맞는 gate와 정식 앱 실기를 마친다. `build.sh`의 VERSION을 새 버전으로 올리고
`./build.sh --app-only --include-model`로 모델 동봉 앱을 만든다.
현재 사용 중인 앱을 바꾸지 않고 이미 검증한 앱을 서명하려면 `--app`으로 해당 경로를 지정한다.

```bash
python3 scripts/release/macos.py prepare --app Clonie.app --work .build/release-<version>
python3 scripts/release/macos.py submit --work .build/release-<version>
python3 scripts/release/macos.py finish --work .build/release-<version>
```

- `prepare`: 배포용 인증서 확인 → 별도 폴더에 앱 복사 → MCP/앱 순서로 Hardened Runtime·타임스탬프 서명.
  앱에는 마이크 entitlement만 추가한다. 일상 개발 앱의 서명과 권한 상태는 바꾸지 않는다.
- `submit`: Apple에 업로드하고 제출 ID 저장. 기다리는 동안 세션을 유지할 필요는 없다.
- `finish`: Apple의 **Accepted** → 공증 증명 첨부(staple) → 서명·staple·Gatekeeper·`syspolicy_check`
  → ZIP 생성 → 다시 압축을 풀어 같은 검사. 모두 통과해야 최종 ZIP과 SHA가 기록된다.
- 처리 중이면 같은 작업 폴더로 `finish`를 나중에 다시 실행한다. 업로드 실패가 불확실하면
  `xcrun notarytool history --keychain-profile clonie-notary`와 해당 ID의 `info`를 대조하고
  `state.json`의 `submission_id`를 복구한 뒤 이어간다. 자동 중복 제출하지 않는다.
- 거절된 요청은 `xcrun notarytool log <id> --keychain-profile clonie-notary <log.json>`으로 원인을 확인한다.
- 서명 변경은 실제 동작에 영향을 줄 수 있다. **공증된 앱의 첫 실행·마이크·시스템 오디오·MCP·검색**을
  별도 시험 자료로 확인한다. 공증 통과가 기능 실기 통과를 대신하지 않는다.

검증된 ZIP의 버전·SHA로 공개 README/INSTALL/설치기/Cask/릴리스 노트를 함께 갱신한다.
발행 후 공개 URL에서 다시 받은 ZIP의 SHA와 압축 해제 후 보안 판정을 확인한다.
앱별 Gatekeeper 예외, quarantine 제거, 전역 보안 해제를 공증 성공으로 취급하지 않는다.
서명 팀/요구사항이 바뀌므로 이전 설치의 마이크·캡처 권한이 다시 필요할 수 있다.

## 검증과 출처

`python3 tests/check_macos_release.py`는 잘못된 인증서·공증 미승인·첨부 실패·중복 업로드 등
실패 경계를 검사한다. Apple 도구 응답을 대체하는 시험이며 실제 공증 증거는 `state.json`과 Apple 제출 ID다.

- [Apple: Developer ID](https://developer.apple.com/developer-id/)
- [Apple: 공증 작업 흐름](https://developer.apple.com/documentation/Security/customizing-the-notarization-workflow)
- [Apple: Hardened Runtime 마이크 권한](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input)
