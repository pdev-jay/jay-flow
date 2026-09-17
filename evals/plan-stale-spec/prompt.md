---
name: plan-stale-spec
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]
---

본드 삭제하고 다시 붙이면 무한 루프 돌아. 기기가 인증 실패로 끊으면 우리가 바로 cleanup 하고, 또 붙고, 또 실패하고, 끝이 없어. 지금은 실패 1번에 바로 정리하거든 — 실패 2번 세고 나서 정리하도록 카운터 넣자. 로그는 logs/device_01.log에 있어.

되물을 게 있으면 plan 초안을 먼저 전부 제시하고, 질문은 초안 아래에 권장 답과 함께 붙여줘. 한 번에 보고 싶어.
plan 세우자.
