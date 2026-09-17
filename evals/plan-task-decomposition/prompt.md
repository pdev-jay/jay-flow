---
name: plan-task-decomposition
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]
---

골격 잡자. README에 그려둔 구조대로 core, scanner, queue, reconnector 만들어서 compose에서 조립되게. 지금은 core가 import도 안 되는 상태야.

그리고 링크 실패하면 무한 대기하는 거 bounded로 바꿔. 설정에 link_timeout 넣어둔 건 있는데 어디로도 안 가고 있어.

되물을 게 있으면 plan 초안을 먼저 전부 제시하고, 질문은 초안 아래에 권장 답과 함께 붙여줘. 한 번에 보고 싶어.
plan 세우자.
