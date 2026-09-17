# Clonie 1.0.5 · 자료 검색과 대화 기록 개선

이번 알파에서는 자료 편집과 대화 후 기록 확인을 다듬었습니다.

**[Mac용 다운로드](https://github.com/qoal1201/clonie-preview/releases/download/preview-20260917-clonie1/Clonie-preview-20260917-clonie1-arm64.zip)** · [설치 도움말](https://github.com/qoal1201/clonie-preview/blob/main/INSTALL.md)

macOS 26 이상 · Apple Silicon(M 시리즈)용입니다. 기본 검색·편집에는 AI 계정이나 API 키가 필요하지 않습니다.

### 달라진 점

- Markdown을 서식을 보며 편집하고 자동 저장할 수 있습니다. PDF·Word 자료도 가져올 수 있습니다.
- 기록을 선택하면 대화 본문이 바로 열립니다.
- 마이크만 사용하는 경우 내가 말한 질문으로 저장소의 자료를 찾습니다.
- 사용 시작 시 마지막 자료 범위·입력 선택을 기억하고, 준비가 끝난 권한 항목은 숨깁니다.
- 외부 AI가 MCP로 저장한 문서의 변경 전후를 앱에서 확인할 수 있습니다.

### 처음 실행할 때

이 버전은 **미공증 알파**입니다. Apple이 확인할 수 없다는 경고가 나오면 공식 배포 파일인지 확인한 뒤,
시스템 설정 → 개인정보 보호 및 보안 → ‘그래도 열기’에서 Clonie를 허용할 수 있습니다.
음성 사용에 필요한 권한은 별도로 요청합니다.

### 써보며 알려주세요

내 자료를 질문으로 찾고, 문서를 조금 고친 뒤 다시 검색해 보세요.
원하는 자료가 나오지 않거나 실행·음성 사용에서 막히면 [사용 피드백](https://github.com/qoal1201/clonie-preview/issues/new?template=feedback.yml)을 남겨 주세요.
개인 문서 원문은 올리지 않아도 됩니다.

아직 실제 사람의 음성 인식과 다른 Mac의 첫 사용을 검증 중입니다. 관련도가 높아도 질문의 답이 자료에 없을 수 있습니다.
Intel Mac·Windows는 지원하지 않으며 macOS 27 실행은 아직 검증하지 않았습니다.

<details>
<summary>검증 범위·파일 무결성·라이선스</summary>

개발 Mac에서 화면 검사 791개·Swift 시험 383개, ZIP 설치기 검사 4개를 통과했습니다.
정식 앱의 준비 화면·설정 복원·저장소 복귀를 확인했습니다. 자동 검사 통과가 다른 Mac 첫 실행이나 실제 음성 품질을 보장하지는 않습니다.

파일: `Clonie-preview-20260917-clonie1-arm64.zip`
SHA-256: `221d12730bd7ae669dfb594cf5e6be1e4ebbf08b197532d4f6ba45d0d9cbac79`

[라이선스 범위](https://github.com/qoal1201/clonie-preview/blob/preview-20260917-clonie1/LICENSING.md)

</details>
