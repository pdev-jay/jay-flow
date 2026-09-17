#!/usr/bin/env bash
# jay-flow 신선도 게이트 (PreToolUse, matcher: Skill).
# jay-flow:build 호출일 때만 동작. 원격 upstream이 있고 로컬 HEAD가 그보다 뒤면 exit 2로 차단하고
# 뒤처진 커밋 목록을 stderr로 모델에 돌려준다. 그 외(다른 스킬·원격 없음·git 아님)는 exit 0.
set -uo pipefail
input=$(cat)
case "$input" in *'jay-flow:build'*) ;; *) exit 0 ;; esac

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || exit 0
git fetch -q 2>/dev/null || exit 0
behind=$(git rev-list --count "HEAD..$upstream" 2>/dev/null) || exit 0
if [ "${behind:-0}" -gt 0 ]; then
  {
    echo "[jay-flow 신선도 게이트] 로컬 HEAD가 upstream($upstream)보다 ${behind}커밋 뒤다. build를 시작하지 말고 사용자에게 알려라 — 뒤처진 커밋:"
    git log --oneline "HEAD..$upstream"
  } >&2
  exit 2
fi
exit 0
