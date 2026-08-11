# jay-flow

plan → build → review → done. 대화로 plan을 완성하고, task로 나눠 구현하고, plan과 대조해 리뷰하는 경량 개발 루프.

## 설계 원칙

CIDD 실측에서 살아남은 것만 남겼다:

- **lens fan-out은 버리고, 구현 fan-out은 쓴다.** 검사 축은 체크리스트로 메인이 직접 채운다 — 상시 5(구조·의존성·영향 범위·잠재 에러·범위) + 조건부 4(보안·롤백/마이그레이션·성능/비용·테스트 가능성, 트리거될 때만). lens 서브에이전트 없음 — **사용자의 수정 지시가 마찰 소스**다. (실측: 강한 모델 + 적극적 사용자 반복이면 lens fan-out 한계효용 ~0; 반면 파일이 겹치지 않는 독립 task의 병렬 구현은 순수 wall-clock 이득.) 체크리스트는 사용자가 대충 보는 날의 바닥. 예외 하나: review의 diff 자체 검토만 fresh-context `reviewer` **하나**에 위임한다 — 축을 흩는 fan-out이 아니라 컨텍스트 위생(빌드 잔해 없는 눈)이고, 모델은 세션 모델 그대로다.
- **모델 배치 = 3슬롯.** 추론·판정(plan 완성, drift 판정, review)은 **메인 세션 = 상위 모델**, 구현은 **순차·병렬 불문 `jay-flow:builder` = sonnet**(예외: 자명한 초소형 task와 에스컬레이션만 메인 직접). builder가 repair 캡을 소진하면 **메인이 직접**(그게 모델 에스컬레이션). 메인이 구현을 안 하는 이유는 단가만이 아니라 컨텍스트 위생 — 구현 잔해가 차면 판정 품질이 떨어진다. plan·review의 모델은 플러그인이 못 박는다 — **세션을 상위 모델로 돌리는 것이 사용법**이다.
- **베이스가 stale이면 그 위의 모든 판정이 무효.** build 시작 전 `git fetch`로 로컬이 upstream보다 뒤지지 않은지 확인하고, 뒤면 멈춘다. plan의 영향 범위 실측도 drift 기준선(체크포인트 커밋)도 전부 시작 시점 HEAD에 기대는데, **오라클은 stale 베이스를 못 잡는다** — 뒤처진 트리 위에서도 전부 green일 수 있다. (실측: 원격 세션이 올린 0.2.0을 모른 채 13일 묵은 클론에서 0.1.7을 얹는 사고가 실제로 났다.)
- **에이전트 팀 기능은 안 쓴다.** 서브에이전트에 이름을 붙이지 않고, 완료된 builder를 `SendMessage`로 재개하지 않는다. 교정은 새 builder 재-dispatch. 재개가 아끼는 건 재독 비용뿐인데, 이름 붙은 에이전트는 팀 로스터에 영구 등재돼 build 한 번에 수십 줄이 쌓이고(실측: task 21개 build가 25줄), 가용성이 환경(팀 모드 on/off)에 좌우된다 — **절차가 환경에 의존하면 안 된다.**
- **검증 바닥은 오라클.** test/type/build green이 완료 기준. 자기보고는 증거가 아니다. 고위험 표면(auth·schema·billing·concurrency·외부 I/O)은 변경 라인의 테스트 도달까지 확인.
- **plan 재주입.** task마다 해당 plan slice를 다시 읽고 시작한다. (실측: 에이전트는 plan에서 표류하고, 주기적 재주입이 위반을 줄인다.)
- **사람 게이트는 둘, 그 사이는 연속 주행.** plan 승인(앞)과 review 판정(뒤)만 사람이 멈춰 세우는 지점이다 — 승인에 진행 지시가 붙으면 build→review는 입력 대기 없이 이어진다(build 정지 조건 미green·plan 오류·고위험 미도달은 예외). cidd:auto식 풀 auto는 넣지 않는다 — 사용자가 마찰 소스라는 전제와 모순이고, 긴 자율 주행은 CIDD의 영역이다.
- **상태는 최신 plan 파일 하나, 이력은 버전 파일로.** plan은 `.plans/<slug>/v1.md, v2.md…`로 쌓인다 — **내용 변경은 새 버전**(맨 위 `변경:` 한 줄, 이전 버전 수정 금지), **체크박스·status는 최신 버전에 in-place**(실행 상태는 버전 사유 아님). 유효본 = 최고 버전. 별도 state machine 없음. 부수 효과: review가 diff-plan 차이를 버전 이력과 대조해 "승인된 변경 vs 이탈"을 구분한다.

## 흐름

```
대화 ──▶ plan (상시 5축 + 조건부 축 체크 + 사용자 수정 반복, 승인까지)
              │ 승인 → task 분해 → .plans/<slug>/v1.md (내용 변경 시 v2, v3…)
              ▼
         build (베이스 신선도 확인 → 구현은 전부 builder(sonnet): 공유분 순차 → 독립분 병렬 →
                오라클 green → 메인이 drift 판정, 막히면 메인 에스컬레이션
                → 전체 green 후 단순화 pass: 우발적 복잡도 제거, 동작·계약 불변)
              ▼
         review (오라클 → diff vs plan → 잠재 에러 재검 → advisory)
              │ 사용자 accept
              ▼
            done (plan status: done)
```

## 스킬

| 스킬 | 하는 일 |
|---|---|
| `jay-flow:plan` | 대화로 plan 완성(상시 5축 + 조건부 축 + 미해결·전제 + self-check + 사용자 반복), 승인 시 task 분해·저장 |
| `jay-flow:build` | 베이스 신선도 게이트(`git fetch`, 뒤지면 정지), 구현은 전부 `builder`(sonnet) — 공유분 순차·독립분 병렬, 오라클 green(캡 3, 초과 시 메인 에스컬레이션), 판정은 메인, task green마다 체크포인트 커밋, 통합 red는 귀속→repair 사다리, 전체 green 후 단순화 pass(동작·계약 불변) |
| `jay-flow:review` | 전체 오라클 → diff vs plan → diff 자체 검토는 fresh-context `reviewer`(세션 모델) 위임, advisory 보고, accept 시 done |

## 설치

```bash
# GitHub — 이 repo가 자체 마켓플레이스를 포함한다
/plugin marketplace add pdev-jay/jay-flow
/plugin install jay-flow@jay-flow-cc
/reload-plugins

# 또는 로컬 dev (소스 라이브 로드)
claude --plugin-dir /Users/nucode/00_personal/00_claude_plugin/jay-flow
```

산출물은 대상 repo의 `.plans/<slug>/`에 모인다(작업 항목당 폴더, 버전당 파일). 커밋에 안 싣으려면 `.gitignore`에 `.plans/` 한 줄 — 버전 파일이 이력이라 git 없이도 추적된다.

## CIDD와의 관계

같은 척추(plan→build→review→done), 다른 몸. CIDD의 멀티에이전트 기계(lens 마찰 루프·adversarial conformance·judge panel)는 안 읽을 diff·긴 자율 주행·오류비용 큰 표면에서 쓰는 물건이고, jay-flow는 사용자가 diff를 직접 읽고 plan을 직접 반복하는 일상 작업용이다. 필요하면 같은 repo에서 병용할 수 있다(산출물 폴더가 `.plans/` vs `.cidd/`로 분리).
