# Clonie logo

앱 아이콘과 메뉴 막대 자산은 2026-09-15 사용자 확정 브랜드 패키지의 문서·궤도 실루엣을 사용한다.
형태를 다시 생성하지 않고 전달된 SVG/PNG를 코드 자산으로 변환했다.

- `ClonieDock.png`: 전달된 1024px 크림 심볼·차콜 타일 PNG 원본.
- `Clonie.icns`: `ClonieDock.png`에서 만든 16px부터 1024px까지의 macOS 아이콘 묶음.
- `ClonieMenuTemplate.png`: 여백 없는 `ClonieMenuTemplate.svg`를 래스터화한 AppKit 템플릿 이미지.
- `ClonieMark.png`: 어두운 앱 헤더에 쓰는 256px 크림 심볼. `ChatHTML.swift`에 같은 바이트를 data URI로 넣는다.
- `source/`: 확정된 Dock SVG, 메뉴 템플릿 SVG, 크림/차콜 심볼 SVG.
- `source-logo.png`: 2026-09-10 당시 전달 원본. 이전 브랜드 자산의 출처 기록으로 보존한다.

메뉴 심볼은 원본 비율을 유지하며 앱에서 폭 18pt, 높이 약 15.1pt로 표시한다.
`./assets/branding/generate-app-assets.sh`로 메뉴 PNG, 헤더 PNG/data URI, ICNS를 재현할 수 있다.
`build.sh`가 ICNS와 메뉴 막대 이미지를 `Clonie.app` Resources에 복사한다.
