#!/usr/bin/env bash
# jay-flow vs dryforge — plan 단계 비교 스위트.
#
#   evals-compare/run.sh [추가 claude plugin eval 옵션...]
#   예) evals-compare/run.sh --model claude-sonnet-5 --runs 1 --case cmp-booking-cancel   # 파일럿
#   SIDES=dryforge evals-compare/run.sh --case 'cmp-b*'    # 한쪽만 (사용량 한도 창에 나눠 돌릴 때)
#
# 배치를 나눠 돌렸으면 summarize.py에 결과 JSON을 전부 넘겨 합산한다 — 한도 에러 run은 자동 제외.
#
# cases/<case>/ 가 단일 원본이다. prompt.md의 {{INVOKE}} 줄만 도구별로 바꿔 두 곳에 렌더한다:
#   jay-flow → evals-compare/render/jay-flow/   (target = 이 repo, with-without → jay-flow + baseline)
#   dryforge → vendor/dryforge/claude/evals-compare/  (target = dryforge, --ablation none — baseline 중복 방지)
# fixture.src가 있으면 evals/<그 케이스>/fixture.sh를 그대로 쓴다(fixture 복제 금지).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
DRYFORGE_SHA=904f25742c9e5a36b09753a7f5ea8c26801b0fa9   # v1.3.7
VENDOR="$HERE/vendor/dryforge"
OUT="$HERE/results/$(date +%Y%m%d-%H%M%S)"

if [ ! -d "$VENDOR/.git" ]; then
  git clone -q https://github.com/prekuter/dryforge "$VENDOR"
fi
git -C "$VENDOR" cat-file -e "$DRYFORGE_SHA" 2>/dev/null || git -C "$VENDOR" fetch -q origin
git -C "$VENDOR" checkout -q "$DRYFORGE_SHA"

render() {  # $1 = 출력 디렉터리, $2 = {{INVOKE}} 치환 문장
  rm -rf "$1"
  for c in "$HERE"/cases/*/; do
    local name d
    name="$(basename "$c")"
    d="$1/$name"
    mkdir -p "$d"
    cp -R "$c/graders" "$c/case.yaml" "$d/"
    if [ -f "$c/fixture.src" ]; then
      cp "$ROOT/evals/$(cat "$c/fixture.src")/fixture.sh" "$d/fixture.sh"
    else
      cp "$c/fixture.sh" "$d/fixture.sh"
    fi
    sed "s|{{INVOKE}}|$2|" "$c/prompt.md" > "$d/prompt.md"
  done
}

render "$HERE/render/jay-flow" "/jay-flow:plan"
render "$VENDOR/claude/evals-compare" "/dryforge:ready"

mkdir -p "$OUT"
COMMON=(--scaffold --trust-plugin --allow-tools Bash Write Agent
        --model claude-opus-5-5 --judge-model sonnet --no-publish -j 4 --threshold 0)

# 두 run이 같은 인자를 받도록 사용자 옵션은 뒤에 붙인다(--model 등 덮어쓰기 가능).
SIDES="${SIDES:-jay-flow dryforge}"
case " $SIDES " in *" jay-flow "*)
  claude plugin eval "$ROOT" --eval-dir evals-compare/render/jay-flow \
    "${COMMON[@]}" --json "$OUT/jay-flow.json" "$@" ;;
esac
case " $SIDES " in *" dryforge "*)
  claude plugin eval "$VENDOR/claude" --eval-dir evals-compare --ablation none \
    "${COMMON[@]}" --json "$OUT/dryforge.json" "$@" ;;
esac

python3 "$HERE/summarize.py" "$OUT"/*.json | tee "$OUT/summary.md"
