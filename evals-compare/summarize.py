#!/usr/bin/env python3
"""jay-flow vs dryforge 비교표. run.sh가 호출한다.

    python3 evals-compare/summarize.py <result.json> [<result.json> ...]
    python3 evals-compare/summarize.py evals-compare/results/*/*.json      # 여러 배치 합산

어느 도구의 결과인지는 suite.plugins로 판별한다. jay-flow 결과의 without arm이 baseline(플러그인 없음)이다.
사용량 한도로 시작도 못 한 run(인프라 에러)은 점수·평균에서 빼고 따로 센다 — 모델 실패가 아니다.
점수는 하네스 점수를 쓰지 않고 여기서 다시 계산한다: dryforge는 --ablation none으로 돌아 skill-fired 같은
with-only grader가 점수에 섞이므로, 세 arm 모두 같은 grader 집합(skill-fired 제외)의 가중 평균으로 맞춘다.
"""
import json
import re
import statistics
import sys
from collections import defaultdict

EXCLUDE = {"skill-fired"}
INFRA = re.compile(r"session limit|usage limit|rate limit", re.I)
ARMS = ("jay-flow", "dryforge", "baseline")


def run_score(run):
    gs = [g for g in run["graders"] if g["name"] not in EXCLUDE]
    total = sum(g["weight"] for g in gs)
    return sum(g["weight"] for g in gs if g["passed"]) / total if total else 0.0


def mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else float("nan")


def load(paths):
    """{arm: {case: [run, ...]}}, {arm: 인프라 에러 수}"""
    runs = {a: defaultdict(list) for a in ARMS}
    infra = defaultdict(int)
    for p in paths:
        d = json.load(open(p))
        tool = d["suite"]["plugins"][0]["name"]
        for c in d["cases"]:
            for arm_key, rs in c["arms"].items():
                label = tool if arm_key == "with" else "baseline"
                for r in rs or []:
                    if r.get("error") and INFRA.search(r["error"]):
                        infra[label] += 1
                    else:
                        runs[label][c["name"]].append(r)
    return runs, infra


def stats(rs):
    return {
        "n": len(rs),
        "score": mean([run_score(r) for r in rs]),
        "cost": mean([r.get("costUsd") for r in rs]),
        "sec": mean([r.get("durationSeconds") for r in rs]),
        "turns": mean([r.get("turns") for r in rs]),
        "errors": sum(1 for r in rs if r.get("error")),
        "fired": sum(1 for r in rs for g in r["graders"] if g["name"] == "skill-fired" and g["passed"]),
    }


def main(paths):
    runs, infra = load(paths)
    cases = sorted({c for a in ARMS for c in runs[a]})

    print("## 케이스별 (점수 = skill-fired 제외 가중 평균, 비용·시간·턴 = run 평균, 한도 에러 run 제외)\n")
    print("| 케이스 | arm | n | 점수 | $/run | 초/run | 턴 | 로드 | 에러 |")
    print("|---|---|---|---|---|---|---|---|---|")
    for name in cases:
        for a in ARMS:
            rs = runs[a].get(name)
            if not rs:
                print(f"| {name} | {a} | 0 | — | — | — | — | — | — |")
                continue
            s = stats(rs)
            fired = "—" if a == "baseline" else f"{s['fired']}/{s['n']}"
            print(f"| {name} | {a} | {s['n']} | {s['score']:.2f} | {s['cost']:.2f} | {s['sec']:.0f} | "
                  f"{s['turns']:.1f} | {fired} | {s['errors']} |")

    # 전체 평균은 세 arm이 모두 run을 가진 케이스만으로 낸다 — 케이스 구성이 다르면 비교가 안 된다.
    common = [c for c in cases if all(runs[a].get(c) for a in ARMS)]
    print(f"\n## 전체 (세 arm 공통 케이스 {len(common)}개: {', '.join(common) or '없음'})\n")
    print("| arm | runs | 점수 | $/run | 초/run | 턴 | 한도 에러로 제외 |")
    print("|---|---|---|---|---|---|---|")
    for a in ARMS:
        rs = [r for c in common for r in runs[a][c]]
        if rs:
            s = stats(rs)
            print(f"| {a} | {s['n']} | {s['score']:.2f} | {s['cost']:.2f} | {s['sec']:.0f} | {s['turns']:.1f} | {infra[a]} |")
        else:
            print(f"| {a} | 0 | — | — | — | — | {infra[a]} |")

    print("\n## grader별 통과 (통과/run)\n")
    for name in cases:
        print(f"**{name}**\n")
        per = {}
        for a in ARMS:
            acc = {}
            for r in runs[a].get(name, []):
                for g in r["graders"]:
                    p, n = acc.get(g["name"], (0, 0))
                    acc[g["name"]] = (p + int(g["passed"]), n + 1)
            per[a] = acc
        gnames = sorted({g for acc in per.values() for g in acc})
        print("| grader | " + " | ".join(ARMS) + " |")
        print("|---|---|---|---|")
        for g in gnames:
            cells = [f"{per[a][g][0]}/{per[a][g][1]}" if g in per[a] else "—" for a in ARMS]
            print(f"| {g} | " + " | ".join(cells) + " |")
        print()


if __name__ == "__main__":
    main(sys.argv[1:])
