# Clonie 플러그인

쓰던 AI에서 내 Markdown 자료를 찾고, 문서 보완을 요청합니다. AI가 보낸 변경 제안은 Clonie 앱에서 검토하고 승인합니다.

Clonie 1.1.0 이상과 AI 도구를 같은 Mac에 설치해 사용합니다. 앱의 기본 검색·편집은 플러그인 없이도 사용할 수 있습니다.

## 설치

1. [Clonie 앱을 설치](https://github.com/qoal1201/clonie-preview/blob/main/INSTALL.md)하고 한 번 실행해 사용할 Markdown 폴더를 선택합니다.
2. 터미널에서 아래 명령을 실행합니다.
3. 새 Codex 또는 **Work locally** 대화에서 Clonie 플러그인을 선택합니다.

```bash
/bin/bash /Applications/Clonie.app/Contents/Resources/CloniePlugin/install.sh codex
```

앱이 사용자 응용 프로그램 폴더에 있다면 명령의 `/Applications/Clonie.app`을 `~/Applications/Clonie.app`으로 바꿉니다.
설치기는 Codex CLI가 없으면 설치된 ChatGPT/Codex 데스크톱 앱의 실행 파일을 찾습니다.
별도의 Clonie 계정·API 키·서버 설정은 필요하지 않습니다.

공식 플러그인 목록에는 아직 등재되지 않았으며, 현재는 앱에 포함된 설치기를 사용합니다.
Claude Code용 설치는 위 명령의 마지막 인자를 `claude`로 바꿉니다. 실제 계정 사용은 아직 검증하지 않았습니다.

설치 후 AI에 다음과 같이 요청해 연결을 확인합니다.

> Clonie에 연결된 저장소 경로를 확인하고 문서 하나를 찾아 읽어줘. 참고한 경로도 알려줘.

AI가 알려준 저장소가 앱에서 선택한 폴더인지 확인하세요.

## 사용하기

**자료를 찾아 작업에 활용하기**

> Clonie에서 이번 작업과 관련된 기록을 찾아 읽고, 그 내용을 참고해서 도와줘.

**문서 보완을 제안받기**

> 이 문서에 오늘 결정한 내용을 반영하는 변경 제안을 보내줘.

Clonie의 **변경** 탭에서 제안을 비교·수정·승인합니다. 승인 전에는 원문이 바뀌지 않습니다.
승인 후 같은 AI에 문서를 다시 읽도록 요청하면 저장된 내용을 이어서 활용할 수 있습니다.

AI의 프로젝트 폴더와 Clonie의 자료 폴더는 달라도 됩니다. 프로젝트 없는 Work locally에서도 앱이 선택한 폴더를 사용합니다.
외부 AI가 읽은 문서는 해당 AI 서비스에서 처리됩니다. [개인정보 안내](https://github.com/qoal1201/clonie-preview/blob/main/PRIVACY.md)를 참고하세요.

## 지원 환경

| 사용 환경 | 지원 상태 |
| --- | --- |
| 로컬 Codex·Codex CLI | 검색·읽기·변경 제안·앱 승인 후 재조회 확인 |
| Work locally | 프로젝트 없는 새 대화에서도 같은 흐름 확인 |
| Claude Code·Cowork | 설치 구성 제공, 실제 계정 사용은 미검증 |
| 일반 ChatGPT Chat·원격 Work | 이 로컬 플러그인의 지원 대상이 아님 |

사용 확인은 macOS 26의 한 Mac에서 진행했습니다.

## 스킬

플러그인에는 다음 스킬이 포함되어 있습니다. 원하는 일을 자연어로 요청하면 AI가 필요한 스킬을 선택합니다.

| 스킬 | 용도 |
| --- | --- |
| `clonie` | 자료 검색·읽기와 문서 보완 제안 |
| `clonie-init` | 설치·연결 확인과 문제 해결 |
| `clonie-session-record` | 요청한 현재 대화의 핵심을 기록으로 제안 |

직접 지정하려면 Codex에서는 `$clonie`·`$clonie-init`, Claude Code에서는 `/clonie:clonie`·`/clonie:clonie-init`을 사용할 수 있습니다.

## 업데이트

1. Clonie를 정상 종료하고 [최신 앱으로 업데이트](https://github.com/qoal1201/clonie-preview/blob/main/INSTALL.md#업데이트)합니다.
2. 앱을 한 번 연 뒤 위 설치 명령을 다시 실행합니다.
3. 새 AI 대화에서 Clonie를 선택하고 연결된 폴더를 확인합니다.

앱과 AI의 플러그인 캐시는 따로 갱신됩니다. GitHub 소스 변경만으로 기존 설치가 자동 업데이트되지는 않습니다.

## 문제 해결

**앱이나 저장소를 찾지 못합니다.** Clonie를 실행해 자료 폴더를 선택한 뒤 새 AI 대화에서 다시 연결하세요.
앱을 옮겼다면 새 위치에서 한 번 실행합니다. 1.0.6 이하의 앱은 최신 버전으로 업데이트해야 합니다.

**AI가 다른 폴더를 봅니다.** 앱에서 폴더를 바꾼 뒤에는 새 대화에서 Clonie를 선택하세요.
기존 대화는 연결 당시의 폴더를 유지할 수 있습니다. AI에 연결된 저장소 경로를 확인해 달라고 요청하세요.

**플러그인이 보이지만 문서를 읽지 못합니다.** 지원되는 로컬 환경인지, AI의 도구 접근이 허용되어 있는지 확인하세요.
“Clonie 연결을 확인하고 복구해줘”라고 요청하면 `clonie-init` 스킬로 진단할 수 있습니다.
이전에 수동 MCP 연결을 등록했다면 새 플러그인의 읽기를 확인한 뒤 중복된 옛 Clonie 연결만 비활성화하세요.

**변경 요청 후에도 파일이 그대로입니다.** Clonie의 **변경** 탭에서 승인 대기 제안을 확인하세요.
원문에는 승인한 내용만 저장됩니다.

해결되지 않으면 [사용 피드백](https://github.com/qoal1201/clonie-preview/issues/new?template=feedback.yml)을 남겨주세요.
소스에서 설치하거나 플러그인을 수정하려면 [개발 안내](https://github.com/qoal1201/clonie-preview/blob/main/CONTRIBUTING.md#플러그인-개발)를 참고하세요.

라이선스는 동봉한 [PolyForm Perimeter 1.0.1](LICENSE)입니다. 기존 MIT 권리와 제3자 고지를 보존합니다.
