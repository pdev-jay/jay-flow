---
type: llm
weight: 3
---

제시된 plan의 **task 분해**(Tasks 섹션, 또는 작업 순서·병렬 여부를 서술한 부분)를 평가한다. 안건은 "골격 잡자 — core, scanner, queue, reconnector. 그리고 실패 시 무한 대기하는 거 bounded로 바꿔"다.

배경 사실:
- `core.py`의 `build_core()`는 `from workers.scanner import Scanner`, `from workers.queue import Queue`, `from workers.reconnector import Reconnector`를 모듈 최상단에서 import하고 생성자에서 셋을 **인스턴스화**한다. `workers/` 디렉터리는 아직 없어서 `python3 -c "import core"`는 `ModuleNotFoundError`다. 즉 core는 워커 셋(최소한 그 클래스 이름·생성자 시그니처)이 존재해야 import조차 된다 — core task를 워커 task보다 먼저 두면 그 task는 단독으로 오라클 green이 안 난다.
- `app/compose.py`는 `Settings`(scan_interval, queue_depth, reconnect_backoff, link_timeout)를 읽어 `build_core(...)`를 호출하는 유일한 조립 지점이다. 워커 옵션 배선과 `link_timeout` 전달(bounded 변경)이 모두 이 파일을 지난다. `core.py`도 워커 인스턴스화와 `start()`의 `wait_for_link()` 호출(타임아웃 전달 지점)을 함께 갖는다. 따라서 "워커 배선" task와 "bounded 대기" task는 `compose.py`·`core.py`에서 겹친다.
- `tests/test_characterization.py`는 현재 동작을 고정한다: `wait_for_link(timeout=None)`이 받아들여지고 `_deadline is None`이며, `timeout=5`를 줘도 `_deadline is None`(타임아웃 무시). bounded로 바꾸면 이 테스트(특히 두 번째)는 red가 된다. bounded 변경 task가 이 파일을 담당 파일에 넣지 않으면, 그 task는 green이 안 나거나 다른 task가 이 파일을 고쳐야 한다.
- 플러그인의 build 규칙: task 담당 파일이 disjoint면 병렬, 겹치면 순차. "공유분"(다른 task가 기대는 것)은 먼저 순차 처리.

PASS 조건 (전부 충족):
- **인스턴스화 의존 순서**: 워커 3개(또는 그 계약/인터페이스·생성자 시그니처를 정하는 task)가 core 조립(`build_core` 배선) task보다 **먼저**이거나, core task가 "계약만 먼저(공유분) → 배선은 워커 뒤"로 분리돼 있다. core→workers import·인스턴스화 의존을 근거로 언급한다.
- **공유 파일 순차**: `app/compose.py` 또는 `core.py`를 건드리는 task가 둘 이상이면 그 task들은 순차(공유분/겹침분)로 표시되거나 하나의 task로 합쳐져 있다. 같은 파일을 건드리는 두 task를 병렬(독립분)로 표시하지 않는다.
- **characterization 충돌**: `tests/test_characterization.py`가 bounded 변경 task의 담당 파일 목록에 포함되거나, 선행 task에서 갱신·삭제하도록 명시돼 있다. 즉 "동작 변경"과 "현재 동작을 단언하는 테스트 갱신"이 한 task이거나 명시적 순서로 묶여 있다.

FAIL 조건 (하나라도):
- core 조립 task가 워커 task보다 먼저이면서 인스턴스화 의존(워커 없이는 import 불가)을 언급하지 않는다.
- `compose.py` 또는 `core.py`를 함께 건드리는 task들을 병렬·독립으로 표시한다.
- `tests/test_characterization.py`를 언급하지 않거나, bounded 변경 task와 분리해 두고 어느 task가 갱신하는지 정하지 않는다.
- 코드를 이미 수정했다고 말한다.

Tasks 섹션이 아직 없고(승인 전) 작업 순서만 서술한 경우에도 위 세 조건을 그 서술에 대해 같은 기준으로 판정한다. 구조 plan을 별도 안건으로 분리하겠다고 한 경우, 이번에 제시한 plan의 task 순서에 대해 판정한다.
