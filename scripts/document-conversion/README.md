# 문서 변환 런타임

파일 선택·문맥 메뉴·파일 드롭은 `importDocuments`로 연결되며 PDF·DOCX는 이 도구로 변환한다.
Markdown은 그대로 저장하고, TXT·HWPX는 기존 로컬 추출기를 사용한다.

## 설치와 실행

- 지원 환경: Apple silicon, macOS 26 이상. Intel용 설치는 제공하지 않는다.
- `build.sh`가 이 폴더를 앱의 `Contents/Resources/document-conversion/`에 복사한다.
  앱은 `Bundle.main.resourceURL`에서 찾으며 개발자 체크아웃·venv에 의존하지 않는다.
- 최초 PDF·DOCX 가져오기에서 Python, 고정 의존성, 공개 모델을 내려받는다.
  기본 위치는 `~/Library/Application Support/Clonie/DocumentConversion/v1/`이다.
  QA는 시험 볼트 옆의 별도 런타임 경로를 사용한다.
- 설치 단계는 GitHub·PyPI·Hugging Face에 접속하며 문서 경로를 받지 않는다.
  의존성 설치 후 필수 PDF 파이프라인을 오프라인으로 초기화해야 `ready`를 쓴다.
- `VERSION`은 변환 리소스의 내용 해시만 합친다. 앱을 다른 경로로 옮겼다는
  이유만으로 설치를 반복하지 않는다. 리소스 내용이 바뀌면 다시 준비한다.
- 실제 변환은 macOS `sandbox-exec`의 네트워크 거부 정책과 Python 소켓 차단을
  함께 적용한다. 외부 서비스·외부 플러그인·telemetry를 끄고 한국어/영어 macOS OCR을 쓴다.
  Markdown에는 본문과 머리말·꼬리말 영역을 포함한다. AI 요약을 만드는 단계는 아니다.

## 고정 버전

전체 Python 패키지는 [requirements.lock](requirements.lock)에 고정했다.

| 구성 | 고정값 |
| --- | --- |
| 독립 Python | CPython 3.12.6, python-build-standalone 20240909, arm64 아카이브 SHA-256 검증 |
| 변환 | docling-slim 2.126.0 / docling-core 2.96.0 |
| OCR | ocrmac 1.0.1 |
| 표 처리 의존성 | opencv-python-headless 5.0.0.93 |
| 레이아웃 모델 | `docling-project/docling-layout-heron` @ `8f39ad3c0b4c58e9c2d2c84a38465abf757272d8` |
| 표 모델 | `docling-project/docling-models` @ `fc0f2d45e2218ea24bce5045f58a389aed16dc23` |

## 실패와 복구

원본은 변환 전에 목적지의 `원본/`에 보존한다. 실패·취소 후 앱의 가져오기 기록에서
재시도하면 `.clonie/imports/` 영수증과 보관 원본을 사용한다. 외부 원본을 다시 선택할 필요가 없다.
완료된 문서와 사용자가 고친 변환 문서를 덮어쓰지 않는다.

설치 취소는 실행 중인 자식 프로세스를 종료하고 설치 잠금을 정리한다. macOS의 원자적 PID 잠금으로
동시 설치와 잠금 복구를 직렬화한다. 이전 설치의 PID 없는 잠금은 생성 중인 작업을 건드리지 않도록
30초 기다린 뒤 재시도할 때 복구한다. PID 기록이 실패해도 종료 정리를 실행한다. 실패한 설치에는
새 `ready` 표시를 남기지 않는다. 연결·여유 공간 문제를 해결한 뒤 다시 시도한다.
최근 설치/변환 오류는 런타임의 `last-runtime.log`에 있다.

준비된 런타임도 재사용 전에 Python 실행과 변환 필수 모듈 import를 오프라인으로 확인한다.
필수 모델 파일은 `runtime-manifest.json`의 경로·크기·수정 시각과 대조하고, 수정 시각이 바뀐
파일은 SHA-256도 확인한다. 변환 실패 후 같은 런타임의 다음 준비에서는 필수 모델 전체의
SHA-256을 검사한다. 정상 런타임이면 문서 변환이 실패했다는 이유만으로 다시 내려받지 않는다.

검증에 실패하면 `ready`를 무효화하고 필요한 부분을 다시 준비한다. 실행 불가능한 Python과
손상된 모델 폴더는 라이선스·모델 설명 파일을 포함해 런타임 안의 `recovered.*`에 보관한 뒤
교체한다. 필수 모듈이 손상되면 고정 의존성을 재설치하고, 중단된 의존성 복구도 다음 준비에서
이어간다. 모델만 손상되고 버전·의존성이 정상이면 패키지 재설치를 생략한다.
이 복구는 사용자 볼트의 원본·Markdown·가져오기 영수증을 변경하지 않는다.

잠금·취소·실패 재시도·리소스 경로 변경·런타임 손상 복구 회귀검사는 저장소 루트에서
`python3 tests/check_document_conversion_bootstrap.py`로 실행한다. 임시 런타임과 가짜 Python을
사용하며 다운로드·앱 빌드·GUI 조작을 하지 않는다.

## 출처와 라이선스 보존

Python 배포본의 `lib/python3.12/LICENSE.txt`, 설치된 wheel의 `*.dist-info`와 포함된
LICENSE/NOTICE 파일, 모델 스냅샷의 README 및 부속 파일을 제거하거나 축약하지 않는다.
확인한 모델 README의 라이선스 표기는 레이아웃이 `apache-2.0`, 표 모델이
`cdla-permissive-2.0`이다. Python 패키지와 모델에 하나의 라이선스를 일괄 적용하지 않는다.

기존 앱의 `ThirdPartyNotices/`는 빌드에서 별도로 보존한다. 이 메모는 라이선스 원문이나
배포 검토를 대신하지 않는다. 런타임·모델을 앱에 선탑재해 배포하는 방식으로 바꿀 경우에는
현재 내려받아 보존하는 출처·고지까지 함께 포함하는지 다시 확인한다.
