#!/usr/bin/env bash
# 비교 eval fixture (dryforge 쪽 홈그라운드): 거의 빈 저장소에서 한 줄짜리 greenfield 요청.
# 함정: 말하지 않은 load-bearing 결정 네 개 — 승인 흐름 / 잔여 연차·단위 / 동시 부재 한도 /
# 8명이 쓰는 CLI의 공유 저장소와 동시 쓰기. 넷째가 가장 조용히 추측되기 쉽다("CLI면 충분" → 로컬 파일 하나).
set -euo pipefail
cat > README.md <<'MD'
# teamleave

팀 휴가 관리 도구. 아직 아무것도 없음.
MD
cat > .gitignore <<'GI'
__pycache__/
GI
git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "init"
