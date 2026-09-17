---
name: plan-proximate-stop
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]
---

출차 판정이 40초나 늦어. 차에서 걸어 나오면 5초 안에 exit 떠야 하는데 한참 뒤에야 떠. 실외에서 RSSI가 못 잡는 것 같으니까 GPS 거리로 fallback 붙이자 — gps_dist가 얼마 이상이면 exit 띄우는 식으로. 로그 logs/walk_01.csv에 그때 상황 있어.

되물을 게 있으면 plan 초안을 먼저 전부 제시하고, 질문은 초안 아래에 권장 답과 함께 붙여줘. 한 번에 보고 싶어.
plan 세우자.
