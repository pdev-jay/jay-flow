# jay-flow evals

`claude plugin eval` 스위트. 목적: 구조 선택(builder 위임 / 병렬 / 메인 직접)을 논쟁이 아니라 점수·비용으로 비교한다.

## 실행

```bash
# 기본 2-arm(with / without plugin) — baseline 대비 Δ까지
claude plugin eval . --scaffold --allow-tools Bash Write Edit \
  --model claude-fable-5-1 --judge-model sonnet \
  --max-cost-usd 30 --no-publish --json evals/results/latest.json

# 변형 비교 중엔 with-arm만(비용 절반)
claude plugin eval . --scaffold --allow-tools Bash Write Edit --ablation none \
  --model claude-fable-5-1 --judge-model sonnet --max-cost-usd 15 --no-publish \
  --json evals/results/<variant>.json
```

- `--scaffold` 없으면 fixture가 안 만들어져 케이스가 무의미하다.
- `--allow-tools Bash Write Edit` 없으면 구현 도구가 세션에서 제거된다.
- `--model`은 고정한다 — 모델 롤아웃을 플러그인 회귀로 오인하지 않기 위해.
- **grader·fixture·정규식 확인용 run은 `--model claude-sonnet-5 --runs 1 --ablation none`으로.** Fable 5.1은 변형 비교·최종 baseline에만 쓴다(단가 5배). 2026-09-17 첫날 지출 $17 중 절반 이상이 grader 검증 run이었다.

## 변형 비교 절차

구조 변형은 **브랜치**로 만든다(플러그인 복사 금지). 같은 스위트를 브랜치마다 돌리고 JSON을 비교한다.

| 변형 | 바꾸는 것 |
|---|---|
| baseline | 없음 (builder = 세션 모델 low effort, 독립분 병렬) |
| builder-sonnet | `agents/builder.md`: `model: sonnet`, effort 미지정 (0.3.x까지의 기본) |
| sequential | build SKILL 3·4단계: 독립분도 순차 |
| main-direct | build SKILL 4단계: 메인이 직접 구현, builder 미호출 (미측정) |

### 2026-09-17 측정 (build-ledger, 3 run, model claude-fable-5-1, judge sonnet)

| 변형 | run당 비용 | run당 시간 | 메인 턴 | 결과 grader |
|---|---|---|---|---|
| 병렬 · builder sonnet | $1.04 | 124s | 21.7 | 전부 통과 |
| 병렬 · builder 세션 모델 low | $1.10 | 120s | 11.3 | 전부 통과 |
| 순차 · builder sonnet | $1.20 | 175s | 22.3 | 전부 통과 |

- builder 모델: sonnet과 세션 모델 low effort는 비용·시간이 노이즈 범위에서 같다. 문서(Fable 5.1 migration guide)가 "저가 모델로 가기 전 low Fable을 평가하라"고 하므로 **세션 모델 low effort를 기본으로 채택**(0.4.0). task가 커지면 재측정 필요 — 이 fixture는 task 3개짜리다.
- 병렬 vs 순차: 순차가 시간 +41%, 비용 +15%. 독립 task가 2개뿐인 fixture에서도 병렬이 이기므로 **병렬 fan-out 유지**.
- 결과 품질은 세 변형 모두 동일(만점). 차이는 경로·비용·시간뿐.
- 주의: sandbox에서 git이 완전히 막히는 run이 있어(`Operation not permitted`) 체크포인트 커밋 grader는 환경 노이즈를 탄다. 점수 비교는 결과 grader 기준으로 본다.

비교 지표(케이스 1개일 때 `costUsd`·`durationSeconds`가 곧 케이스 비용):

```bash
for f in evals/results/*.json; do
  jq -r '[input_filename, .aggregates.overallScore, .costUsd, .durationSeconds] | @tsv' "$f"
done
```

## 케이스

### build-ledger
승인된 plan(task 3: 공유분 1 + 파일 disjoint 독립분 2)을 `plan대로 구현해줘`로 build. Python 표준 라이브러리만, 테스트 10개 red → green.

- **결과 grader**(점수): `oracle.txt`에 `Ran 10 tests … OK` / 파일 3개 생성 / 테스트 파일 무수정 / plan 밖 파일 없음 / 최종 보고가 실제 출력을 인용.
- **경로 grader**(with-only 지표, 점수 제외): build 스킬 발화 / builder Agent dispatch / 체크포인트 커밋 ≥ 3 / review 미호출.

결과와 경로를 분리한 이유: 점수는 "맞게 만들었나"만 재고, 경로는 "플러그인이 설계대로 움직였나"를 따로 본다. 변형 비교에서 경로 지표는 달라지는 게 정상이다.

### plan-ledger
동작하는 ledger 패키지 + 계약 문서(README: 카테고리는 대소문자 무시) + 실제 버그(`parse_line`이 카테고리를 정규화하지 않아 `food`/`Food`가 따로 집계). 사용자가 증상과 재현 명령을 **서술**하고 "plan 세우자".

- **결과 grader**(점수): `진단 + red` 라벨 / 재현 명령을 실제로 Bash로 실행 / 원인 사슬(`←`) / 상시 5축 + 미해결·전제 섹션 / `구조 관례:` / `수정 지점:` / 잠재 에러의 `검증:` / 질문에 `권장` 답 / 승인 전 `.plans/` 미생성 / llm: 사슬이 report(근인)에서 멈추지 않고 parse·Entry 계약(뿌리)까지 갔는가(가중 3).
- **경로 grader**: plan 스킬 발화 / Edit·Write 0회.

plan 스킬 텍스트를 바꿀 때(강조 제거, self-check 재구성 등) 이 케이스로 before/after를 잰다. 실행:

```bash
claude plugin eval . --case plan-ledger --scaffold --allow-tools Bash --ablation none \
  --model claude-fable-5-1 --judge-model sonnet --max-cost-usd 15 --no-publish --trust-plugin \
  --json evals/results/plan-<variant>.json
```

## 알려진 sandbox 특성 (macOS)

- sandbox 안에서 `git`이 xcrun shim을 경유하지 못해 실패할 수 있다. 에이전트는 `/Library/Developer/CommandLineTools/usr/bin/git` 절대경로로 우회한다 — `tool_used` grader의 `input_match`는 절대경로·`-C`·`-c` 옵션이 끼어도 잡히게 쓴다.
- run의 trace(`trace.jsonl`)는 임시 디렉터리에 있어 종료 후 사라진다. 디버깅할 땐 `--keep-temp`.

## 토큰 프로파일 (2026-09-17, `evals/tools/profile.py`)

`--keep-temp`로 돌린 run의 transcript에서 뽑는다. Fable 5.1 list price, 1 run.

| | uncached in | cache write | cache read | output (thinking) | 합계 |
|---|---|---|---|---|---|
| plan main (7 req) | $0.00 | $0.65 (32K, 1h) | $0.05 (179K) | $0.47 (9.4K / 4.4K) | $1.16 |
| build main (15 req) | $0.00 | $0.63 (31K, 1h) | $0.11 (424K) | $0.43 (8.5K / 1.7K) | $1.16 |
| build builder ×3 (12 req) | $0.00 | $0.29 (23K, 5m) | $0.03 (113K) | $0.13 (2.6K / 0) | $0.45 |

읽는 법:
- **cache write가 절반 이상**이다. 컨텍스트에 새로 들어오는 토큰은 전부 1h 캐시 쓰기($20/M, 입력 단가의 2배)로 한 번 과금된다. 메인의 첫 요청은 하네스 시스템 프롬프트 ~11K이고, 그 위에 스킬 본문(plan ≈ 13~17K, build ≈ 7K)이 얹힌다. plan run의 25% 안팎이 plan 스킬 텍스트 자체다.
- 캐시 읽기는 잘 된다(7% 이하). 하네스 소관이라 플러그인이 할 일 없음.
- output은 40%. thinking은 plan에서 절반, build 메인에선 20%뿐 — build 메인의 output 대부분은 보이는 텍스트·도구 호출이라 effort를 낮춰도 크게 안 줄어든다.
- builder 하나 spawn ≈ $0.15(fresh 프리픽스 ~8K 쓰기). 소형 task를 따로 spawn하면 이 비용이 그대로 붙는다.
- 이 fixture는 도구 출력이 12KB뿐이라 오라클 출력 절삭(builder 규칙 5)의 효과는 여기서 0이다. 실제 repo에서 `/cost` 전후로 잰다.

결정(cost-optimize 2026-09-17): 적용 = eval 개발 run은 Sonnet(README 위), 오라클 출력 절삭(builder 규칙 5·build 6단계). skip = build 스킬 `effort: medium`(상한 ≈ build의 5~13%인데 sweep이 $6.6 — 회수에 build 30~60회, 그리고 이 fixture는 판정 품질 저하를 못 본다), plan 스킬 추가 절삭(품질 위험, 안전한 몫은 ~4%), builder 배칭(설계 변경, 실제 task 크기에서 재평가).

## 어려운 plan 케이스 (2026-09-17, hillclimb용)

실제 `.plans/` 이력 4개 저장소·31개 슬러그·`변경:` 58건을 분류해 가장 자주 뒤집힌 형태 8개를 자족형 fixture로 합성했다(태그 `hard`). 각 케이스는 llm 루브릭(w3) 하나가 핵심 신호이고, 나머지는 형식·경로 grader다.

| 케이스 | 유도하는 실패 | 실제 근거 |
|---|---|---|
| plan-stale-spec | 옛 사양 사본으로 전제, 카운터가 루프를 못 끊는데 채택 | ble-pairing v5→v6, display v1→v2 |
| plan-proximate-stop | 근인(RSSI 불안정)에서 멈추고 GPS fallback으로 점프 | gps-exit v1→v4 |
| plan-backend-asymmetry | alpha 로그만 보고 공용 임계 — beta는 도달 불가 | ble-pairing v4·v7 |
| plan-unverified-code-facts | grep 없이 "사용 중" 단언, legacy 테스트·config 누락 | speed-report v2·v3 |
| plan-untestable-seam | seam 추출 대신 Connection 리플렉션 우회 | ble-pairing v2→v3 |
| plan-wide-refactor | expand→migrate→contract 미분해, sample·wiring 누락 | slice4·5·6 |
| plan-deferred-scope | "나중에"로 미룬 경로의 silent 성공을 방치 | multi-beacon v2 |
| plan-task-decomposition | core가 워커보다 먼저, 공유 파일 병렬, characterization 충돌 | skeleton v2, slice2 v2 |

프롬프트 공통 줄: "되물을 게 있으면 plan 초안을 먼저 전부 제시하고, 질문은 초안 아래에 권장 답과 함께" — 단일 턴 eval이라 질문만 하고 멈추면 채점이 불가능해서 넣었다.

hillclimb 상태: `evals/hillclimb/plan/` (`_state.json`에 train/test 분할, seed 42). 판정은 test 3개의 delta.

### hillclimb 결과 (2026-09-17 종료)

| 라운드 | 변경 | train | test | 판정 |
|---|---|---|---|---|
| baseline | — | 0.948 | 0.864 | |
| v1 | wide refactor 판정을 개수 → "동시 red" 기준 | 0.931 | 0.879 | keep (노이즈 범위, 겨냥 루브릭 1/3→2/3, 비용 동일) |
| v2 | 제시 초안도 `##` 헤딩 | — | — | 미측정 적용 (스킬 결함 수정) |

Fable 5.1, judge sonnet, 케이스당 3 run. 기록: `evals/hillclimb/plan/`.

- **헤딩 형식 노이즈.** 초안을 굵은 글씨 헤딩으로 쓴 run은 section grader 6종을 한꺼번에 잃어 run 점수가 0.25 떨어진다. 케이스당 3 run에서 delta 0.05 미만은 판정 불가다. v2가 이 원인을 막는다.
- **Sonnet 5는 이 스위트의 대리 모델로 못 쓴다.** 같은 스킬(v1)에서 w3 루브릭 통과가 Fable 19/24, Sonnet 4/24다. 실패 양상이 달라 Sonnet에서 다듬으면 Fable 개선이 안 된다. hard 스위트는 plan을 실제로 돌리는 세션 모델로 잰다. 라운드당 Fable $38, Sonnet $12.
- **남은 약점.** plan-deferred-scope는 두 모델 모두 w3 0/3. test 세트라 이걸 보고 고치지 않았다 — 재개 시 split 재조정부터.
