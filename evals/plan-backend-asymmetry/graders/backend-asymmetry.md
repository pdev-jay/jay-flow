---
type: llm
weight: 3
---

제시된 plan이 두 백엔드 모두에서 성립하는 설계인지 평가한다.

배경 사실: 저장소에는 페어링 백엔드가 둘 있고(`backends/alpha.py`, `backends/beta.py`) 둘을 동시에 지원하는 것이 계약이다. 공통 복구 로직 `core/recovery.py`는 `FAILED` 이벤트를 임계(현재 1)만큼 세면 `cleanup()`을 호출하고 `BONDED`에서 카운터를 리셋한다. alpha는 페어링 실패마다 `FAILED`를 내므로 한 세션에 여러 번 나온다(실기기 로그 `logs/alpha.log`에 5회). beta는 한 세션에 `FAILED`를 **첫 실패 1회만** 내고 이후 실패는 `DISCONNECTED`로 나온다(`Recovery`는 `DISCONNECTED`를 무시한다). 재시도는 세션 안에서 일어나고 세션은 `BONDED` 또는 `cleanup()`으로만 끝난다. 따라서 임계를 2로 올리기만 하면 beta에서는 `cleanup()`이 영원히 호출되지 않는다. `tools/simulate.py --backend beta --failures 3 --threshold 2`가 이를 실행으로 보여 준다(`FAILED_events=1 cleanups=0`). 사용자는 alpha 로그만 언급했다.

PASS 조건 (전부 충족):
- 원인·배경 또는 잠재 에러에 "beta는 세션당 `FAILED`를 1회만 내므로 임계 2에 도달하지 못한다(cleanup이 안 된다)"는 취지의 지적이 있다.
- 접근이 두 백엔드 모두에서 성립한다. 예: 백엔드별로 실패 신호의 의미를 정규화해서(beta의 후속 `DISCONNECTED`를 실패로 세거나 beta 어댑터가 실패마다 `FAILED`를 내게 하는 등) 공통 카운터에 넣는다 / 임계를 백엔드별 설정으로 분리한다 / `FAILED` 횟수 대신 "BONDED 없이 지난 시도 수·시간" 같은 성공 신호 기반으로 바꾼다. 어느 것이든 beta에서 cleanup이 실제로 일어남을 설명한다.
- Tasks에 beta 동작을 검증하는 테스트(또는 simulate 재관측)가 포함된다.
- alpha 재현(`tools/replay.py` 또는 `tools/simulate.py`)을 실제로 실행한 출력을 인용한다.

FAIL 조건 (하나라도):
- 접근이 `FAILURE_THRESHOLD`(또는 동등한 상수)를 2로 올리는 것뿐이고 beta에서의 결과를 다루지 않는다.
- `backends/beta.py`의 방출 규칙을 확인하지 않고 두 백엔드가 같은 빈도로 `FAILED`를 낸다고 전제한다.
- beta 언급이 아예 없다.
- 실행 출력 없이 사용자의 서술만 근거로 진단한다.
- 코드를 이미 수정했다고 말한다.
