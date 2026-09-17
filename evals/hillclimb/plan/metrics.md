# plan hillclimb metrics

- **score**: `claude plugin eval`의 케이스 점수(가중 grader 통과율, 0~1). 케이스마다 결과 grader(라벨·red 실행·사슬·섹션·전용 정규식·llm 루브릭 w3)와 경로 grader.
- **costUsd / turns / durationSeconds**: run당. guardrail — baseline 대비 노이즈 밖으로 오르면 revert.
- 판정은 **test 3개 케이스의 delta**로 한다. train 5개는 분석·수정에만 쓴다.
