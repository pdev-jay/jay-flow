# v1 — wide refactor 트리거를 개수에서 "동시 red" 기준으로

train 실패: plan-wide-refactor 2/3 (expand→migrate→contract 미분해, sample·wiring 누락). 원인: 스킬 트리거가 "호출부 수십~수백 개"라는 개수에 걸려 있어 11파일짜리 fixture를 wide로 안 봄.
변경: 영향 범위 축(62행)과 task 분해(95행)의 판정 기준을 "한 변경이 여러 파일을 동시에 red로 만들어 단일 task로 green을 못 만드는가"로 바꾸고, exhaustive 소비자 규칙(원자 task 또는 별도 채널)과 contract 단계의 non-owned 테스트·sample 포함을 명시.
근거: 실제 이력 slice3·slice4 v5·slice6 v2.
