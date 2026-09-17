---
name: build-ledger
runs: 3
max_turns: 200
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, TodoWrite]
---

이 저장소의 `.plans/ledger-report/v1.md`는 승인된 plan이다. plan대로 구현해줘.

조건:
- 전체 오라클은 `python3 -m unittest discover -s tests -t .` 이다.
- 구현이 끝나면 마지막에 `python3 -m unittest discover -s tests -t . > oracle.txt 2>&1` 을 실행해 결과를 파일로 남겨라.
- build까지만 한다. review 단계는 호출하지 마라.
- 최종 메시지에는 생성한 파일 목록과 오라클의 실제 출력(마지막 줄들)을 적어라.
