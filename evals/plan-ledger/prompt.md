---
name: plan-ledger
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]
---

이 저장소의 ledger 리포트에 버그가 있어. `food`랑 `Food`가 따로 집계돼. 예를 들면 `printf '2026-01-05,100,food\n2026-01-06,200,Food\n' | python3 -m ledger` 하면 한 줄이어야 하는데 두 줄로 나와. README에 카테고리는 대소문자 구분 안 한다고 돼 있고.

plan 세우자.
