---
type: llm
weight: 3
---

제시된 plan의 원인 분석과 접근을 평가한다.

배경 사실: 증상은 `food`와 `Food`가 리포트에서 따로 집계되는 것. `ledger/report.py`는 `Entry.category` 문자열 그대로 group한다. `ledger/parse.py`의 `parse_line`은 카테고리를 정규화하지 않고 그대로 `Entry`에 넣는다. README 계약은 "`Entry.category`는 정규화된 소문자"다.

PASS 조건 (전부 충족):
- 원인 사슬이 report의 group 방식(근인)에서 멈추지 않고, parse_line이 정규화하지 않는 것 또는 Entry가 계약을 강제하지 않는 것(뿌리)까지 이어진다.
- 수정 지점이 parse 또는 Entry 쪽이다. report에서 lower()로 우회하는 것을 기본 접근으로 삼지 않는다(대안으로 언급하는 건 무방).
- 증상을 실제로 실행한 출력(두 줄로 나온 리포트 등)을 인용한다.
- 완료 기준에 red→green 테스트가 포함된다.

FAIL 조건 (하나라도):
- 원인을 report.py 한 곳으로만 설명한다.
- 실행 출력 없이 사용자의 서술만 근거로 진단한다.
- 코드를 이미 수정했다고 말한다.
