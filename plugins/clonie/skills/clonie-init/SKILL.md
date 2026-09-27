---
name: clonie-init
description: Set up or repair the local Clonie plugin connection when the user asks to initialize Clonie, reconnect MCP, change its repository, or a requested Clonie task cannot reach the expected vault. Diagnose the installed app and actual MCP vault before resuming. Do not trigger for general Clonie development discussions.
---

# Clonie 연결 확인과 복구

사용자가 요청한 Clonie 작업을 이어갈 수 있게 연결 문제를 직접 좁힌다. 앱에 별도 AI 연결 버튼은 없다.
사용자의 연결·복구 요청은 해당 Clonie 설정을 고치는 권한이다. 이미 승인된 설치·복구를 다시 묻지 않는다.
일반 조회 요청에서는 읽기 진단부터 진행하고, 설치되지 않은 앱의 다운로드나 다른 연결 삭제로 범위를 넓히지 않는다.

## 먼저 확인

이 스킬 파일 옆의 `scripts/connection.sh`를 **실제 절대 경로**로 찾아 `/bin/bash …/connection.sh --check`를
실행한다. 앱과 저장소 경로만 읽으며 자격 증명·문서 본문·전체 설정은 출력하지 않는다. 이 경로는
플러그인의 MCP 시작에도 쓰인다. `ready_to_start`는 실행 준비일 뿐 현재 AI 연결 성공이 아니다.

Clonie MCP가 있으면 `vault_list(limit: 1)`의 `vaultPath`를 확인한다. 사용자 지정 경로가 우선이며,
없으면 위 진단의 앱 선택 경로와 대조한다. `/var`·`/private/var` 같은 차이는 실제 경로로 비교한다.
경로가 없거나 다르면 해당 연결로 본문 조회·변경 제안을 진행하지 않는다. 현재 과업의 폴더를 대화 중
조용히 바꾸지 않는다. 앱에서 폴더를 바꿨거나 재연결을 요청받았을 때 다시 확인한다.

## 확인한 원인만 복구

- **앱 없음:** 기존 설치 위치가 알려졌으면 그 앱을 한 번 연다. 앱은 실행한 위치를 자체 설정에 등록한다.
  없으면 [공개 설치 안내](https://github.com/qoal1201/clonie-preview)를 따른다. 해당 배포본이 현재
  플러그인과 호환되는지 먼저 확인하며, 공개 알파에 개발판 기능이 있다고 안내하지 않는다.
  임의의 다운로드 주소를 만들지 않는다.
- **앱과 플러그인 버전 불일치:** 진단은 앱의 MCP가 승인 대기 제안 방식을 지원하는지 확인한다.
  지원하지 않으면 앱·플러그인이 함께 맞춰진 배포본으로 업데이트한다. 호환되는 공개 배포본이 아직
  없으면 현재 연결할 수 없는 상태를 알린다. 진단을 건너뛰거나 옛 수동 MCP로 대신 연결하지 않는다.
- **저장소 없음·삭제된 경로:** Clonie에서 사용할 폴더를 한 번 선택하게 한다. 지정받은 폴더가 없으면
  바탕화면·작업 폴더를 임의로 연결하지 않는다. 기존 Markdown을 초기화하거나 이동하지 않는다.
- **플러그인 미설치·비활성:** 호스트의 실제 설치·활성 상태부터 확인한다. 이미 설치돼 있으면 중복
  수동 MCP를 추가하지 않는다. Codex에서는 현재 화면이 제공하는 플러그인 선택으로 Clonie를 활성화한다
  (`@` 선택 등이 제공되는 화면이 있지만 모든 클라이언트에서 같은 방식이라고 가정하지 않는다).
  스킬만 보이는 상태를 MCP 연결로 보고하지 않는다.
  설치를 요청받았으면 진단에서 확인한 앱의 `Contents/Resources/CloniePlugin/install.sh`를
  `/bin/bash`로 실행하고 사용할 호스트 하나(`codex` 또는 `claude`)를 인자로 준다.
  호스트를 특정할 수 없을 때만 묻는다. 설치 완료 뒤에는 실제 MCP 연결을 따로 확인한다.
- **설정은 맞는데 옛 연결:** 호스트가 제공하는 재연결 도구가 있으면 Clonie만 재연결한다.
  Codex CLI의 `mcp`에는 현재 재시작 명령이 없다. 지원되지 않는 `mcp restart`를 실행하거나 프로세스를
  임의 종료하지 않는다. 플러그인 업데이트 후에는 새 대화에서 활성화하는 단계가 필요할 수 있다.
  Claude Code에서는 `/mcp`의 Clonie 연결 상태·재연결을 사용한다. 플러그인 변경은 지원 버전의
  `/reload-plugins`로 반영할 수 있다. 에이전트가 그 UI를 조작할 수 없으면
  사용자가 수행할 그 한 단계와 재개할 요청을 짧게 전달한다.
- **개발판 갱신:** 현재 로컬 marketplace가 이 소스를 가리키는지 확인하고 해당 호스트의 플러그인
  update/install 명령을 사용한다. 캐시 파일을 직접 고치지 않는다. 배포자는 Codex cachebuster도 갱신한다.
- **옛 수동 MCP와 중복:** 명령·인자·설정 범위만 확인한다. 토큰·환경변수 값을 통째로 출력하지 않는다.
  새 플러그인이 실제 대상 저장소를 읽는지 확인한 뒤, 복구 범위에 포함된 이전 Clonie 연결만 정리한다.
  다른 서버·인증·승인 정책은 유지한다.

도구의 승인·접근 거절은 연결 장애와 구별한다. 거절된 자료 접근을 셸이나 별도 서버 실행으로 우회하지 않는다.
사용자 API 키·TypeSafe 키는 로컬 MCP 연결의 조건이 아니다.

## 복구 후 원래 작업 재개

현재 AI에 연결된 MCP의 `vault_list` 경로가 맞으면, 요청에 필요한 문서 하나를 `vault_read`로 확인한다.
설정 저장·진단 성공·실제 읽기 성공을 구별해 짧게 알리고 원래 요청을 이어간다. 아직 호스트 재연결이
필요하면 완료라고 하지 않는다. 같은 실패를 반복 호출하지 말고 필요한 한 단계만 남긴다.

일반 활용은 [clonie](../clonie/SKILL.md), 현재 대화 기록은
[clonie-session-record](../clonie-session-record/SKILL.md)를 따른다. `vault_write`는 제안이며,
원문 반영은 Clonie 변경 탭의 사용자 승인 뒤에만 이루어진다.
