#!/usr/bin/env python3
"""eval run의 토큰·비용 프로파일. `claude plugin eval ... --keep-temp` 뒤 결과 JSON을 넘긴다.

    python3 evals/tools/profile.py evals/results/<run>.json [<run2>.json ...]

main 세션과 서브에이전트를 나눠 uncached input / cache write(1h·5m) / cache read / output(thinking 포함) 토큰과
list-price 비용을 찍는다. 단가는 Fable 5.1 기준(input $10, cache write 1h $20 / 5m $12.5, cache read $0.25, output $50 /M).
다른 모델이면 RATES를 바꾼다.
"""
import collections, glob, json, os, sys

RATES = {"input": 10.0, "cw_1h": 20.0, "cw_5m": 12.5, "cache_read": 0.25, "output": 50.0}


def usage_of(path):
    per = collections.defaultdict(collections.Counter)
    for line in open(path, encoding="utf-8"):
        try:
            m = json.loads(line)
        except ValueError:
            continue
        if m.get("type") != "assistant":
            continue
        u = (m.get("message") or {}).get("usage")
        if not u:
            continue
        c = per[m.get("requestId") or m.get("request_id") or m.get("uuid")]
        c["input"] = max(c["input"], u.get("input_tokens") or 0)
        c["cache_read"] = max(c["cache_read"], u.get("cache_read_input_tokens") or 0)
        c["output"] = max(c["output"], u.get("output_tokens") or 0)
        c["thinking"] = max(c["thinking"], (u.get("output_tokens_details") or {}).get("thinking_tokens") or 0)
        cc = u.get("cache_creation") or {}
        cw_total = u.get("cache_creation_input_tokens") or 0
        cw_1h = cc.get("ephemeral_1h_input_tokens") or 0
        c["cw_1h"] = max(c["cw_1h"], cw_1h)
        c["cw_5m"] = max(c["cw_5m"], cc.get("ephemeral_5m_input_tokens") or (cw_total - cw_1h))
    tot = collections.Counter()
    for c in per.values():
        tot.update(c)
    return len(per), tot


def cost(t):
    return {k: t[k] * RATES[k] / 1e6 for k in RATES}


def report(result_json):
    d = json.load(open(result_json))
    for case in d["cases"]:
        for i, r in enumerate(case["arms"]["with"]):
            tp = r.get("tracePath") or ""
            tmp = os.path.dirname(os.path.dirname(tp))
            projs = glob.glob(os.path.join(tmp, "config", "projects", "*"))
            if not tp or not projs:
                print(f"{case['name']} run{i}: transcript 없음 (--keep-temp로 다시 돌려라)")
                continue
            pd = projs[0]
            groups = (("main", glob.glob(pd + "/*.jsonl")), ("sub", glob.glob(pd + "/*/subagents/*.jsonl")))
            print(f"=== {case['name']} run{i}  reported ${r['costUsd']:.3f}")
            grand = 0.0
            for who, paths in groups:
                T, N = collections.Counter(), 0
                for p in paths:
                    n, t = usage_of(p)
                    N += n
                    T.update(t)
                if not N:
                    continue
                c = cost(T)
                s = sum(c.values())
                grand += s
                print(f" {who:4} files {len(paths)} req {N:3}  in {T['input']:>7,}  cw_1h {T['cw_1h']:>8,}  cw_5m {T['cw_5m']:>7,}  cr {T['cache_read']:>9,}  out {T['output']:>6,} (thinking {T['thinking']:,})")
                print(f"      $ in {c['input']:.3f}  cw {c['cw_1h'] + c['cw_5m']:.3f}  cr {c['cache_read']:.3f}  out {c['output']:.3f}  = ${s:.3f}")
            print(f" computed ${grand:.3f}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
