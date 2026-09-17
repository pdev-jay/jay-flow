---
name: plan-untestable-seam
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]
---

연결 실패했을 때 정리 시퀀스가 반쪽만 도는 것 같아. 실기기에서 잡은 로그가 `logs/cleanup_01.log`에 있으니까 봐봐 — 어떤 실패는 4단계가 다 찍히는데 어떤 건 3단계만 찍혀. 이번엔 테스트 먼저 만들고 고쳐줘.

되물을 게 있으면 plan 초안을 먼저 전부 제시하고, 질문은 초안 아래에 권장 답과 함께 붙여줘. 한 번에 보고 싶어.
plan 세우자.
