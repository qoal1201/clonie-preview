# Clonie logo

2026-09-10 사용자가 만든 PNG 세트를 제공하고 앱 적용을 승인했다.
`source-logo.png`는 전달받은 원본이며 SHA-256은
`a9cd18f0e4ed5acd290a3a1b4e34fa08e1d019dc9cd9d02fbbb649561b001cca`다.

- 왼쪽 컬러 심볼 → `ClonieMark.png`: 앱 헤더·갤럭시 중심. HTML 안에 data URI로 포함한다.
- 가운데 단색 심볼 → `ClonieMenuTemplate.png`: 18pt 메뉴 막대 템플릿용 36px PNG.
- 오른쪽 아이콘 → `ClonieDock.png`, `Clonie.icns`: 앱 번들 아이콘.

세 영역을 투명 여백에 맞춰 분리하고 비율을 유지해 크기만 조정했다.
그림을 재생성하거나 형태·색을 재설계하지 않았다. 원본의 가장자리 질감도 유지된다.
`build.sh`가 icns와 메뉴 막대 이미지를 앱 Resources에 복사한다.
