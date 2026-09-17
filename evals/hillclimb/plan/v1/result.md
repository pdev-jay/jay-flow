# v1 결과 (2026-09-17, fable 5.1, judge sonnet, 3 run/case)

| | base | v1 | Δ |
|---|---|---|---|
| train (5) | 0.948 | 0.931 | -0.017 |
| test (3) | 0.864 | 0.879 | +0.015 |
| test cost/run | $1.24 | $1.25 | — |

케이스별:

| case | base | v1 | Δ | w3 llm pass (base→v1) |
|---|---|---|---|---|
| backend-asymmetry (train) | 0.957 | 1.000 | +0.043 | 2→3 |
| proximate-stop (train) | 0.917 | 0.889 | -0.028 | 3→3 |
| stale-spec (train) | 1.000 | 0.917 | -0.083 | 3→3 |
| task-decomposition (train) | 1.000 | 1.000 | 0 | 3→3 |
| wide-refactor (train, 겨냥) | 0.867 | 0.850 | -0.017 | **1→2** |
| deferred-scope (test) | 0.632 | 0.772 | +0.140 | 0→0 |
| untestable-seam (test) | 0.960 | 0.960 | 0 | 2→2 |
| unverified-code-facts (test) | 1.000 | 0.905 | -0.095 | 3→3 |

노이즈원: `##` 대신 굵은 글씨 헤딩을 쓴 run은 section grader 6종을 한꺼번에 잃는다(run 점수 -0.25). base 2 run, v1 4 run(proximate-stop·stale-spec·unverified-code-facts·wide-refactor). v1은 형식 관련 텍스트를 건드리지 않았다. section grader 제외 시: train 0.950→0.978(+0.028), test 0.853→0.870(+0.017).

판정: test delta +0.015는 노이즈 범위. 겨냥한 wide-refactor 루브릭은 1/3→2/3로 방향은 맞지만 n=3. 회귀 없음, 비용 동일.
