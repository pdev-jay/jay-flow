# jay-flow vs dryforge — plan 단계 비교

[dryforge](https://github.com/prekuter/dryforge) `ready`와 jay-flow `plan`을 같은 fixture·같은 프롬프트로 돌려 점수·비용·시간을 비교한다. 대상은 plan 단계뿐이다 — dryforge `go`는 push된 main과 worktree를 전제해서 eval sandbox의 git 제약에 먼저 걸린다.

## 실행

```bash
evals-compare/run.sh                                   # 본 run: Opus 5.5, 케이스당 3 run, judge sonnet
evals-compare/run.sh --model claude-sonnet-5 --runs 1 --case cmp-booking-cancel --keep-temp   # 파일럿
```

`run.sh`가 dryforge를 고정 SHA(v1.3.7)로 `vendor/`에 클론하고, `cases/`를 두 곳에 렌더한 뒤 eval을 두 번 돌린다.

- jay-flow run: target = 이 repo, `with-without` → **jay-flow + baseline(플러그인 없음)**
- dryforge run: target = `vendor/dryforge/claude`, `--ablation none` (baseline은 한 번만)
- 결과: `results/<timestamp>/{jay-flow,dryforge}.json` + `summary.md`

## 공정성 장치

- **프롬프트는 맨 앞 슬래시 명령만 다르다.** `prompt.md`의 `{{INVOKE}}` → `/jay-flow:plan` / `/dryforge:ready`. dryforge 스킬은 `disable-model-invocation: true`라 Skill 도구로는 호출이 거부된다 — 슬래시 호출만 된다. 자동 발화 여부는 비교 대상이 아니다. 슬래시 호출은 trace에 흔적이 없으므로 `skill-fired`는 init 줄의 plugins 목록으로 로드만 확인한다(로드되면 슬래시 확장은 결정적).
- **결정 드러냄은 결정마다 grader를 따로 둔다.** 전부-아니면-전무 루브릭은 파일럿에서 "환불만 물음"과 "환불·부분 취소를 물음"을 같은 0점으로 만들었다.
- **채점은 형식 중립.** `evals/`의 plan 케이스 grader는 jay-flow 형식(`##` 헤딩, `←`, `진단+red`, `수정 지점:`)을 보므로 여기서 쓰지 않는다. 핵심 루브릭은 `focus: trace`로 transcript 전체를 보고, plan 문서·spec 파일·질문 목록 중 어디에 있든 인정한다.
- **점수는 `summarize.py`가 다시 계산한다.** 세 arm 모두 같은 grader 집합(skill-fired 제외)의 가중 평균. 하네스 점수는 ablation 모드에 따라 with-only grader 포함 여부가 달라져 arm 간 비교가 안 된다.
- **도구는 같다.** Read·Glob·Grep·Skill·TodoWrite·Agent·AskUserQuestion + 운영자 grant Bash·Write. dryforge는 `.dryforge/`에 3-doc을 쓰고 서브에이전트 감사를 돌리므로 Write·Agent가 필요하다. 소스(`.py`) Write와 Edit는 양쪽 모두 0이어야 한다.
- **단일 턴 한계.** dryforge `ready`는 질문 → 답 → spec 순서가 설계다. 프롬프트가 "초안을 먼저, 질문은 아래에"를 요청하지만 dryforge가 질문만 하고 멈출 수 있다 — 루브릭이 질문으로 드러낸 것도 인정하는 이유다.

## 케이스

| 케이스 | 홈그라운드 | 핵심 루브릭(w3) | 추가 |
|---|---|---|---|
| cmp-backend-asymmetry | jay-flow (수정류) | beta는 세션당 FAILED 1회 → 임계 2 도달 불가를 짚고, 두 백엔드에서 성립하는 제안 | 재생 스크립트 실행 |
| cmp-proximate-stop | jay-flow (수정류) | GPS fallback이 아니라 에피소드 종료 조건(뿌리) | 재생 스크립트 실행 |
| cmp-unverified-code-facts | 중립 (기능 변경 + 실측) | legacy 테스트·모듈 등록 실측, profile_cache 참조 0으로 사용자 전제 정정 | |
| cmp-booking-cancel | dryforge (모호한 기능) | 결정별 w1 ×3: 환불 정책 / 다항목 부분 취소 / 대기자 승격 연쇄를 사용자에게 드러냄 | 저장소로 알 수 있는 걸 묻지 않음(w2) |
| cmp-greenfield-leave | dryforge (greenfield) | 결정별 w1 ×4: 승인 흐름 / 잔여 연차 / 동시 부재 / 공유 저장소 | 이미 말한 걸 되묻지 않음(w2) |

앞의 셋은 `fixture.src`가 가리키는 `evals/<케이스>/fixture.sh`를 그대로 쓴다.
