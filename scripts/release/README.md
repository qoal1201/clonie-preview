# macOS 릴리스

코드와 문서는 일반 커밋으로 계속 개선하고, 검증한 앱을 새 버전으로 묶습니다.
기존 Git 이력·태그·설치 파일은 보존합니다. README 수정마다 앱을 다시 빌드하거나 공증할 필요는 없습니다.

1. 관련 테스트와 실제 앱 사용 흐름을 확인합니다.
2. `build.sh`의 버전을 올리고 모델·플러그인을 포함해 앱을 빌드합니다.
3. Developer ID Application 인증서로 별도 배포 앱을 서명합니다.
4. Apple 공증 후 서명·staple·Gatekeeper·압축 재해제 검사를 통과한 ZIP을 사용합니다.
5. ZIP의 실제 SHA-256과 버전을 설치기·Cask·릴리스 노트에 반영합니다.
6. 기존 main 이력 위에 소스와 문서를 커밋하고, 그 커밋에 새 태그와 릴리스를 만듭니다.
7. 공개 URL에서 다시 받은 파일의 SHA-256을 대조합니다.

```bash
python3 scripts/release/macos.py check --app Clonie.app
python3 scripts/release/macos.py prepare --app Clonie.app --work .build/release-<version>
python3 scripts/release/macos.py submit --work .build/release-<version>
python3 scripts/release/macos.py finish --work .build/release-<version>
```

Apple 인증 정보는 Keychain의 `clonie-notary` 프로필을 사용합니다. 인증서 개인 키·비밀번호는
소스·명령 인자·로그에 넣지 않습니다. Apple 계정과 인증 정보 준비는 계정 소유자가 직접 진행합니다.
`status: verified` 전에는 다운로드 링크를 새 파일로 바꾸지 않습니다.

변경 내역은 [CHANGELOG](../../CHANGELOG.md), 사용자 설치·업데이트 안내는 [INSTALL](../../INSTALL.md)에 둡니다.
공식 플러그인 목록 제출은 GitHub 앱 릴리스와 별도 절차이며, 등재가 확인되기 전에는 설치 경로로 안내하지 않습니다.
