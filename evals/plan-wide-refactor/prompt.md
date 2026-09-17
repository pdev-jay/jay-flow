---
name: plan-wide-refactor
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]
---

lib 쪽 손 좀 보자. 진단용 이벤트 `Event.DIAGNOSTIC` 추가하고, `BleError` 던지는 거 전부 typed `Failure` 반환으로 바꾸자 — `lib/failure.py` 자리는 비워뒀어. 구 `BleError`는 없애고.

되물을 게 있으면 plan 초안을 먼저 전부 제시하고, 질문은 초안 아래에 권장 답과 함께 붙여줘. 한 번에 보고 싶어.
plan 세우자.
