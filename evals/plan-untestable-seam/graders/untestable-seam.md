---
type: llm
weight: 3
---

제시된 plan이 "테스트 먼저 만들고 고쳐줘"라는 요청을 테스트 가능성 관점에서 올바르게 다뤘는지 평가한다.

배경 사실: `app/handler.py`의 `on_connect_failed(conn: Connection, status)`는 `except SdkError:` 블록 안에 정리 시퀀스 4단계(구독 해제 → 캐시 삭제 → 본드 삭제 → 상태 리셋)를 인라인으로 갖고 있다. 본드 삭제만 `if status not in RETRYABLE:`로 감싸여 있어 status 0x16·0x08·0x3E에서 건너뛰어진다(README 계약은 "status와 무관하게 4단계 전부"). `Connection`은 `vendor/sdk/connection.py`에 있고 생성자가 실제 `DeviceHandle`이 아니면 `RuntimeError("real device required")`를 던진다. `DeviceHandle`은 `vendor/sdk/device.py`의 `open_device()`로만 얻는데 sandbox에는 BLE 어댑터가 없어 항상 실패한다. README는 `vendor/`를 "수정 금지 — 업데이트 시 통째로 덮어씀"이라고 명시한다. 실기기 로그 `logs/cleanup_01.log`에 status=0x16 실패 후 3단계만 찍힌 흔적이 있고, `python3 tools/replay.py logs/cleanup_01.log`가 그 위반을 출력한다. 정리 단계들은 전부 주소(addr) 문자열만 받는 `app/` 레지스트리 함수들이라 Connection 없이도 호출할 수 있다.

PASS 조건 (전부 충족):
- `## 테스트 가능성` 섹션(또는 그에 준하는 명시 항목)에 "Connection은 실기기 없이 인스턴스화 불가"라는 사실을 적고, 그래서 현재 형태의 `on_connect_failed`는 단위 테스트로 red를 만들 수 없다고 인정한다.
- 접근/Tasks가 정리 시퀀스를 Connection에 의존하지 않는 함수(주소·status 같은 식별자만 받는 것)로 추출하는 seam task를 두고, 그 다음에 그 함수에 red 테스트를 거는 순서다. 또는 라벨을 `진단 + red 불가 — 기기 의존`으로 두고 대체 증거로 `logs/cleanup_01.log`(또는 replay 출력)를 인용한 뒤, seam 추출 후 red→green을 완료 기준에 넣는다. 둘 중 하나면 된다.
- `vendor/`를 수정하는 task가 없다.

FAIL 조건 (하나라도):
- "테스트 먼저"를 그대로 첫 task로 두고 Connection을 mock/patch하면 된다고만 적는다(seam 추출 없이).
- `vendor/` 파일을 수정·패치하는 task가 있다.
- `red 불가` 라벨 없이 지금 red를 만들 수 있다고 주장하면서 실제로 실행한 명령과 출력이 없다.
- 로그·replay 출력 등 실제 관측 없이 사용자 서술만으로 진단한다.
- 코드를 이미 수정했다고 말한다.
