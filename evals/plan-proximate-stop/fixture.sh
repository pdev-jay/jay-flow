#!/usr/bin/env bash
# jay-flow eval fixture (plan, hard): RSSI 기반 출차(exit) detector + 실외 도보 로그.
# 함정: 증상은 "판정이 40초 늦다"이고 사용자는 GPS fallback을 제안한다. 진짜 원인은 detector/episode.py가
#       문턱 아래 샘플 1개만으로 에피소드를 닫아 누적 변위가 조각나고, 조각마다 EXIT_MIN에 못 미쳐 무판정인 것.
set -euo pipefail
mkdir -p detector logs tools tests
: > detector/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# exit-detector

차량 비콘의 RSSI 스트림으로 "출차(사용자가 차에서 이탈)"를 판정한다. 샘플 주기 0.2s.

계약:
- `exit`는 실제 이탈(비콘에서 5m 이상 멀어짐) 후 **5초 이내** 발화한다.
- 판정은 `detector/episode.py`의 `ExitDetector`가 한다. 입력은 `detector/rssi.py`의 필터를 거친 RSSI.
- `exit`는 스트림당 한 번만 발화한다.

이 증상은 실외 도보에서만 재현된다. 로그는 `logs/` (컬럼 `t,rssi,gps_dist` — `gps_dist`는 검증용 참조 값으로, 판정에는 쓰지 않는다).

재생: `python3 tools/replay.py logs/walk_01.csv`
테스트: `python3 -m unittest discover -s tests -t .`
MD

cat > detector/rssi.py <<'PY'
"""RSSI sample filter: rejects values outside the radio's plausible range."""

RSSI_MIN = -110.0
RSSI_MAX = 0.0


def is_valid(rssi: float) -> bool:
    return RSSI_MIN <= rssi <= RSSI_MAX


class Filter:
    """Drops out-of-range samples and holds the last valid value."""

    def __init__(self):
        self.last = None
        self.dropped = 0

    def feed(self, rssi: float):
        if not is_valid(rssi):
            self.dropped += 1
            return None
        self.last = rssi
        return rssi
PY

cat > detector/episode.py <<'PY'
"""Exit detection from RSSI samples.

An *episode* is a run of samples in which the phone is moving away from the
beacon: the per-sample RSSI drop is at least MOVE_MIN_DB. Displacement (sum of
drops) accumulated inside one episode reaching EXIT_MIN_DB fires `exit`.
"""
from dataclasses import dataclass
from typing import Optional

MOVE_MIN_DB = 0.8
EXIT_MIN_DB = 15.0


@dataclass
class Episode:
    start: float
    end: Optional[float] = None
    displacement: float = 0.0


class ExitDetector:
    def __init__(self):
        self.prev = None
        self.current: Optional[Episode] = None
        self.episodes: list = []
        self.exit_at: Optional[float] = None

    def feed(self, t: float, rssi: float) -> Optional[str]:
        if self.prev is None:
            self.prev = rssi
            return None
        drop = self.prev - rssi
        self.prev = rssi
        if drop >= MOVE_MIN_DB:
            if self.current is None:
                self.current = Episode(start=t)
            self.current.displacement += drop
            if self.exit_at is None and self.current.displacement >= EXIT_MIN_DB:
                self.exit_at = t
                return "exit"
            return None
        self._close(t)
        return None

    def _close(self, t: float) -> None:
        if self.current is None:
            return
        self.current.end = t
        self.episodes.append(self.current)
        self.current = None
PY

cat > logs/walk_01.csv <<'CSV'
t,rssi,gps_dist
0.0,-55.1,0.0
0.2,-55.2,0.0
0.4,-54.9,0.0
0.6,-55.3,0.0
0.8,-55.0,0.0
1.0,-55.1,0.0
1.2,-55.3,0.0
1.4,-55.0,0.0
1.6,-55.3,0.0
1.8,-55.0,0.0
2.0,-55.3,0.0
2.2,-55.2,0.0
2.4,-55.0,0.0
2.6,-54.8,0.0
2.8,-55.2,0.0
3.0,-55.2,0.0
3.2,-54.9,0.0
3.4,-54.7,0.0
3.6,-55.0,0.0
3.8,-55.1,0.0
4.0,-54.7,0.0
4.2,-55.3,0.0
4.4,-54.8,0.0
4.6,-55.1,0.0
4.8,-55.2,0.0
5.0,-55.9,0.2
5.2,-56.8,0.5
5.4,-57.9,0.7
5.6,-58.8,1.0
5.8,-59.9,1.2
6.0,-60.9,1.4
6.2,-61.9,1.7
6.4,-62.9,1.9
6.6,-63.7,2.2
6.8,-64.6,2.4
7.0,-65.5,2.6
7.2,-66.6,2.9
7.4,-67.6,3.1
7.6,-67.2,3.4
7.8,-67.0,3.6
8.0,-67.9,3.8
8.2,-68.9,4.1
8.4,-69.9,4.3
8.6,-70.8,4.6
8.8,-71.9,4.8
9.0,-73.0,5.0
9.2,-73.9,5.3
9.4,-74.9,5.5
9.6,-75.9,5.8
9.8,-77.1,6.0
10.0,-78.1,6.2
10.2,-79.1,6.5
10.4,-80.2,6.7
10.6,-81.1,7.0
10.8,-81.2,7.2
11.0,-80.9,7.4
11.2,-81.3,7.7
11.4,-81.1,7.9
11.6,-81.4,8.2
11.8,-81.0,8.4
12.0,-80.9,8.6
12.2,-81.0,8.9
12.4,-80.8,9.1
12.6,-81.2,9.4
12.8,-81.0,9.6
13.0,-81.0,9.8
13.2,-81.0,10.1
13.4,-81.1,10.3
13.6,-80.9,10.6
13.8,-80.8,10.8
14.0,-81.1,11.0
14.2,-81.0,11.3
14.4,-81.4,11.5
14.6,-81.0,11.8
14.8,-81.0,12.0
15.0,-80.7,12.2
15.2,-80.9,12.5
15.4,-81.2,12.7
15.6,-81.2,13.0
15.8,-81.0,13.2
16.0,-81.4,13.4
16.2,-81.1,13.7
16.4,-81.3,13.9
16.6,-81.4,14.2
16.8,-81.4,14.4
17.0,-80.9,14.6
17.2,-81.4,14.9
17.4,-81.3,15.1
17.6,-81.2,15.4
17.8,-80.8,15.6
18.0,-81.4,15.8
18.2,-81.1,16.1
18.4,-81.1,16.3
18.6,-80.8,16.6
18.8,-80.9,16.8
19.0,-80.8,17.0
19.2,-81.2,17.3
19.4,-81.2,17.5
19.6,-81.2,17.8
19.8,-80.8,18.0
20.0,-82.0,18.2
20.2,-81.3,18.5
20.4,-81.3,18.7
20.6,-81.3,19.0
20.8,-81.3,19.2
21.0,-81.1,19.4
21.2,-81.0,19.7
21.4,-81.3,19.9
21.6,-81.4,20.2
21.8,-81.2,20.4
22.0,-81.2,20.6
22.2,-81.0,20.9
22.4,-80.8,21.1
22.6,-81.0,21.4
22.8,-81.1,21.6
23.0,-81.0,21.8
23.2,-81.0,22.1
23.4,-81.4,22.3
23.6,-80.8,22.6
23.8,-80.9,22.8
24.0,-80.8,23.0
24.2,-80.9,23.3
24.4,-81.2,23.5
24.6,-81.2,23.8
24.8,-81.4,24.0
25.0,-81.0,24.2
25.2,-81.4,24.5
25.4,-81.4,24.7
25.6,-81.3,25.0
25.8,-81.3,25.2
26.0,-81.2,25.4
26.2,-81.4,25.7
26.4,-81.4,25.9
26.6,-81.3,26.2
26.8,-81.4,26.4
27.0,-81.2,26.6
27.2,-81.4,26.9
27.4,-80.8,27.1
27.6,-81.0,27.4
27.8,-81.3,27.6
28.0,-81.3,27.8
28.2,-81.2,28.1
28.4,-81.2,28.3
28.6,-81.4,28.6
28.8,-80.8,28.8
29.0,-80.7,29.0
29.2,-81.1,29.3
29.4,-81.1,29.5
29.6,-81.4,29.8
29.8,-81.4,30.0
30.0,-81.2,30.2
30.2,-81.3,30.5
30.4,-80.9,30.7
30.6,-81.3,31.0
30.8,-81.4,31.2
31.0,-80.8,31.4
31.2,-81.1,31.7
31.4,-81.3,31.9
31.6,-81.1,32.2
31.8,-81.4,32.4
32.0,-81.1,32.6
32.2,-80.8,32.9
32.4,-80.8,33.1
32.6,-81.0,33.4
32.8,-81.3,33.6
33.0,-82.0,33.8
33.2,-81.3,34.1
33.4,-80.9,34.3
33.6,-81.1,34.6
33.8,-80.9,34.8
34.0,-81.2,35.0
34.2,-81.3,35.3
34.4,-80.9,35.5
34.6,-80.8,35.8
34.8,-80.8,36.0
35.0,-80.9,36.2
35.2,-80.9,36.5
35.4,-80.9,36.7
35.6,-81.3,37.0
35.8,-81.1,37.2
36.0,-81.2,37.4
36.2,-81.4,37.7
36.4,-81.4,37.9
36.6,-81.2,38.2
36.8,-81.3,38.4
37.0,-81.0,38.6
37.2,-80.8,38.9
37.4,-81.1,39.1
37.6,-80.8,39.4
37.8,-80.8,39.6
38.0,-80.8,39.8
38.2,-81.2,40.1
38.4,-81.3,40.3
38.6,-81.3,40.6
38.8,-81.3,40.8
39.0,-81.3,41.0
39.2,-81.0,41.3
39.4,-80.8,41.5
39.6,-80.9,41.8
39.8,-81.1,42.0
40.0,-81.0,42.2
40.2,-80.9,42.5
40.4,-81.4,42.7
40.6,-81.0,43.0
40.8,-80.8,43.2
41.0,-80.9,43.4
41.2,-80.9,43.7
41.4,-81.1,43.9
41.6,-81.3,44.2
41.8,-80.9,44.4
42.0,-81.2,44.6
42.2,-80.9,44.9
42.4,-80.8,45.1
42.6,-81.2,45.4
42.8,-81.2,45.6
43.0,-80.8,45.8
43.2,-80.9,46.1
43.4,-81.3,46.3
43.6,-81.4,46.6
43.8,-81.3,46.8
44.0,-80.8,47.0
44.2,-80.9,47.3
44.4,-81.3,47.5
44.6,-80.9,47.8
44.8,-80.8,48.0
45.0,-81.0,48.2
45.2,-81.2,48.5
45.4,-81.1,48.7
45.6,-81.4,49.0
45.8,-81.4,49.2
46.0,-80.8,49.4
46.2,-81.0,49.7
46.4,-81.1,49.9
46.6,-80.8,50.2
46.8,-81.1,50.4
47.0,-80.8,50.6
47.2,-80.9,50.9
47.4,-81.3,51.1
47.6,-81.3,51.4
47.8,-81.2,51.6
48.0,-81.3,51.8
48.2,-81.0,52.1
48.4,-81.3,52.3
48.6,-81.2,52.6
48.8,-81.4,52.8
49.0,-80.8,53.0
49.2,-81.2,53.3
49.4,-81.1,53.5
49.6,-81.0,53.8
49.8,-80.8,54.0
50.0,-82.1,54.2
50.2,-83.3,54.5
50.4,-84.3,54.7
50.6,-85.4,55.0
50.8,-86.5,55.2
51.0,-87.4,55.4
51.2,-88.4,55.7
51.4,-89.4,55.9
51.6,-90.3,56.2
51.8,-91.4,56.4
52.0,-92.3,56.6
52.2,-93.4,56.9
52.4,-94.5,57.1
52.6,-95.6,57.4
52.8,-96.6,57.6
53.0,-97.6,57.8
53.2,-97.6,58.1
53.4,-97.5,58.3
53.6,-97.9,58.6
53.8,-97.6,58.8
54.0,-97.8,59.0
54.2,-97.8,59.3
54.4,-97.5,59.5
54.6,-97.6,59.8
54.8,-97.6,60.0
55.0,-97.5,60.2
55.2,-97.4,60.5
55.4,-97.7,60.7
55.6,-97.6,61.0
55.8,-97.6,61.2
56.0,-97.6,61.4
56.2,-97.5,61.7
56.4,-97.7,61.9
56.6,-97.6,62.2
56.8,-97.6,62.4
57.0,-97.4,62.6
57.2,-97.5,62.9
57.4,-97.4,63.1
57.6,-97.4,63.4
57.8,-97.8,63.6
58.0,-97.6,63.8
58.2,-97.4,64.1
58.4,-97.4,64.3
58.6,-97.8,64.6
58.8,-97.9,64.8
59.0,-97.7,65.0
59.2,-97.9,65.3
59.4,-97.8,65.5
59.6,-97.9,65.8
59.8,-97.5,66.0
CSV

cat > tools/replay.py <<'PY'
"""Replay a walk log through Filter + ExitDetector and print when exit fired.

usage: python3 tools/replay.py logs/walk_01.csv
"""
import csv
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from detector.episode import EXIT_MIN_DB, MOVE_MIN_DB, ExitDetector  # noqa: E402
from detector.rssi import Filter  # noqa: E402

EXIT_DIST_M = 5.0
CONTRACT_S = 5.0


def main(path):
    filt = Filter()
    det = ExitDetector()
    rows = list(csv.DictReader(open(path)))
    actual_exit = None
    for row in rows:
        t = float(row["t"])
        rssi = filt.feed(float(row["rssi"]))
        if rssi is None:
            continue
        det.feed(t, rssi)
        if actual_exit is None and float(row["gps_dist"]) >= EXIT_DIST_M:
            actual_exit = t
    open_ep = det.current
    print(f"samples: {len(rows)}  (t {rows[0]['t']} .. {rows[-1]['t']})  dropped by filter: {filt.dropped}")
    print(f"MOVE_MIN_DB={MOVE_MIN_DB}  EXIT_MIN_DB={EXIT_MIN_DB}")
    print(f"actual exit (gps_dist >= {EXIT_DIST_M}m): t={actual_exit}")
    print(f"exit fired: t={det.exit_at}")
    if det.exit_at is not None and actual_exit is not None:
        delay = det.exit_at - actual_exit
        verdict = "OK" if delay <= CONTRACT_S else "LATE"
        print(f"delay: {delay:.1f}s  (contract <= {CONTRACT_S:.0f}s)  -> {verdict}")
    print("episodes (start  end  displacement):")
    for ep in det.episodes:
        print(f"  {ep.start:5.1f}  {ep.end:5.1f}  {ep.displacement:5.1f} dB")
    if open_ep is not None:
        print(f"  {open_ep.start:5.1f}    -    {open_ep.displacement:5.1f} dB  (open)")


if __name__ == "__main__":
    main(sys.argv[1])
PY

cat > tests/test_episode.py <<'PY'
import unittest

from detector.episode import EXIT_MIN_DB, MOVE_MIN_DB, ExitDetector


def feed_drops(det, t0, drops, step=0.2):
    """Feed samples so that each consecutive drop equals the given value."""
    t = t0
    rssi = -55.0
    det.feed(t, rssi)
    out = []
    for d in drops:
        t += step
        rssi -= d
        out.append(det.feed(t, rssi))
    return out, t


class ExitDetectorTest(unittest.TestCase):
    def test_accumulates_and_fires_at_exit_min(self):
        det = ExitDetector()
        n = int(EXIT_MIN_DB / 1.0)
        out, _ = feed_drops(det, 0.0, [1.0] * n)
        self.assertEqual(out[-1], "exit")
        self.assertIsNone(out[-2])
        self.assertIsNotNone(det.exit_at)

    def test_flat_sample_closes_episode(self):
        det = ExitDetector()
        out, t = feed_drops(det, 0.0, [1.0, 1.0, 0.0])
        self.assertEqual(out, [None, None, None])
        self.assertEqual(len(det.episodes), 1)
        self.assertAlmostEqual(det.episodes[0].displacement, 2.0)
        self.assertEqual(det.episodes[0].end, t)
        self.assertIsNone(det.current)

    def test_below_move_min_never_opens(self):
        det = ExitDetector()
        feed_drops(det, 0.0, [MOVE_MIN_DB - 0.1] * 30)
        self.assertEqual(det.episodes, [])
        self.assertIsNone(det.exit_at)

    def test_fires_once(self):
        det = ExitDetector()
        out, _ = feed_drops(det, 0.0, [1.0] * 40)
        self.assertEqual(out.count("exit"), 1)
PY

cat > tests/test_rssi.py <<'PY'
import unittest

from detector.rssi import Filter, is_valid


class FilterTest(unittest.TestCase):
    def test_rejects_out_of_range(self):
        f = Filter()
        self.assertIsNone(f.feed(-127.0))
        self.assertIsNone(f.feed(12.0))
        self.assertEqual(f.dropped, 2)
        self.assertFalse(is_valid(-127.0))

    def test_passes_valid(self):
        f = Filter()
        self.assertEqual(f.feed(-60.0), -60.0)
        self.assertEqual(f.last, -60.0)
PY

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "exit-detector: rssi episode detector with outdoor walk log"
