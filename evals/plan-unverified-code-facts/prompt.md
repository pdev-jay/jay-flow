---
name: plan-unverified-code-facts
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]
---

지금 세션 끝나고 한 번에 올리는 업로드(session_uploader)를 row 단위 실시간 전송으로 바꾸고 싶어. row 하나 기록될 때마다 바로 보내는 거. 구 경로(summary 올리는 쪽)는 제거하자. profile_cache는 heartbeat가 주기 갱신에 쓰니까 건드리지 말고.

되물을 게 있으면 plan 초안을 먼저 전부 제시하고, 질문은 초안 아래에 권장 답과 함께 붙여줘. 한 번에 보고 싶어.
plan 세우자.
