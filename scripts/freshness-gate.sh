#!/usr/bin/env bash
# jay-flow 신선도 게이트. Claude판과 Codex판이 같은 스크립트를 쓴다.
#   Claude Code: PreToolUse hook(matcher: Skill), 인자 없음, stdin JSON — jay-flow:build 호출일 때만 동작.
#   Codex:       스킬 호출 직전 hook이 없어 build 스킬이 첫 명령으로 직접 부른다 — `--direct` (cwd = 대상 repo).
# 원격 upstream이 있고 로컬 HEAD가 그보다 뒤면 exit 2 + 뒤처진 커밋 목록(stderr).
# fetch 자체가 실패하면(오프라인·인증) exit 0 + '신선도 미검증' 경고
#   (hook 모드: systemMessage·additionalContext JSON / direct 모드: stdout 한 줄).
# 그 외(다른 스킬·원격 없음·git 아님)는 조용히 exit 0.
set -uo pipefail
direct=0
[ "${1:-}" = "--direct" ] && direct=1

if [ "$direct" -eq 0 ]; then
  input=$(cat)
  case "$input" in *'jay-flow:build'*) ;; *) exit 0 ;; esac
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$cwd" ] && cd "$cwd" 2>/dev/null
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || exit 0
if ! git fetch -q 2>/dev/null; then
  msg="[jay-flow 신선도 게이트] git fetch 실패 — upstream($upstream) 대비 신선도 미검증. build는 진행하되 마무리 보고의 미해결에 '베이스 신선도 미검증'을 적어라."
  if [ "$direct" -eq 1 ]; then
    echo "$msg"
  else
    printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$msg" "$msg"
  fi
  exit 0
fi
behind=$(git rev-list --count "HEAD..$upstream" 2>/dev/null) || exit 0
if [ "${behind:-0}" -gt 0 ]; then
  {
    echo "[jay-flow 신선도 게이트] 로컬 HEAD가 upstream($upstream)보다 ${behind}커밋 뒤다. build를 시작하지 말고 사용자에게 알려라 — 뒤처진 커밋:"
    git log --oneline "HEAD..$upstream"
  } >&2
  exit 2
fi
exit 0
