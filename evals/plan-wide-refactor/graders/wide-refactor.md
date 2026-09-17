---
type: llm
weight: 3
---

제시된 plan이 blast radius가 넓은 변경을 올바르게 분해했는지 평가한다.

배경 사실: `lib/events.py`의 `Event`는 공개 Enum(CONNECTED, DISCONNECTED, DATA)이다. `consumers/a.py`, `consumers/b.py`, `service/reconnect.py`, `sample/app.py` 네 파일이 `Event`를 if/elif로 분기하고 마지막 `else`에서 `assert_never(event)`를 부르며, `tools/check_exhaustive.py`(오라클에 포함)가 AST로 네 파일 모두 Event 멤버 전부를 다루는지 검사한다 — 멤버 `DIAGNOSTIC`을 추가하는 순간 네 파일이 동시에 exhaustive 검사에 걸린다. `lib/errors.py`의 `BleError`는 `lib/result.py`가 raise/반환하고, `consumers/a.py`·`consumers/b.py`·`service/session.py`·`service/reconnect.py`가 catch/isinstance하며, `tests/test_wiring.py`(플랫폼 팀 소유 wiring 통합 테스트)가 `BleError(...)` 동등성을 단언하고, `sample/app.py`(README: "공개 API 소비자 예제, CI에 포함")가 catch한다. `lib/failure.py`는 비어 있다. 현재 오라클은 전부 green이다.

PASS 조건 (전부 충족):
- 이 안건을 wide refactor로 인식해 Tasks를 expand → migrate → contract 순서로 분해한다: expand = 새 `Failure` 타입(과 `DIAGNOSTIC` 추가)을 구 형태 옆에 추가, migrate = 호출부를 디렉터리·패키지 배치별로 별도 task로 이전하고 배치마다 green, contract = 남은 참조가 없을 때 `BleError` 삭제.
- contract(또는 migrate) task의 담당 파일 목록에 `tests/test_wiring.py`와 `sample/app.py`가 들어 있다.
- `DIAGNOSTIC` 추가가 exhaustive 분기 4곳(`consumers/a.py`, `consumers/b.py`, `service/reconnect.py`, `sample/app.py`)을 동시에 깨는 것을 명시하고, 그 네 파일을 Enum 추가와 한 task(원자적)로 묶거나, Enum 추가를 BleError 교체와 별도 채널(별도 task 묶음)로 분리해 처리한다.
- 영향 범위가 grep 실측(파일 목록·사용처 열거)에 기반한다.

FAIL 조건 (하나라도):
- 전체를 단일 task 또는 "공유분 하나로 묶음"으로 처리한다.
- `sample/` 또는 `test_wiring`이 어느 task 파일 목록에도 없다.
- `DIAGNOSTIC` 추가가 exhaustive 검사/`assert_never`를 깨는 파급을 언급하지 않는다.
- 코드를 이미 수정했다고 말한다.
