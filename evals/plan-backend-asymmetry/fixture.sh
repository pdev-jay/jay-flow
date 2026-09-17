#!/usr/bin/env bash
# jay-flow eval fixture (plan, hard): 두 페어링 백엔드(alpha/beta) + 백엔드 공통 recovery.
# 함정: 같은 이름 이벤트(FAILED)의 방출 빈도가 백엔드마다 다르다. 실기기 로그는 alpha만 있다.
set -euo pipefail
mkdir -p backends core tools logs tests
: > backends/__init__.py
: > core/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# pairsvc

기기 페어링 서비스. 페어링 스택(백엔드) 두 종을 동시에 지원하고, 그 위에 백엔드 공통 복구 로직(`core/recovery.py`)을 얹는다.

## 계약

- 두 백엔드(`backends/alpha.py`, `backends/beta.py`)를 **동시에** 지원한다. 출하 기기의 절반씩이 각 스택을 쓴다.
- `core/`는 백엔드를 모른다. `core/recovery.py`는 `core/events.py`의 `Event(kind, status)`만 본다. 백엔드는 스택 콜백을 `Event`로 번역해 sink에 넘긴다.
- `Recovery`는 `FAILED`를 `FAILURE_THRESHOLD`회(현재 1) 세면 `cleanup()`을 호출하고, `BONDED`에서 카운터를 0으로 되돌린다. `DISCONNECTED`는 무시한다.
- 세션 = 앱이 페어링을 시작해 `BONDED` 또는 `cleanup()`으로 끝나는 구간. 페어링 재시도는 세션 **안**에서 일어난다(재시도마다 세션을 새로 열지 않는다). `cleanup()`이 세션을 닫고 앱은 그 뒤 새 세션을 연다.

## 백엔드별 이벤트 의미

| 이벤트 | alpha | beta |
|---|---|---|
| `BONDED` | 링크 성립(`onLinkUp`) 시 | 암호화 링크 성립(`onSecureLinkUp`) 시. `onLinkUp`만으로는 나오지 않는다 |
| `FAILED(status)` | 페어링 실패(`onLinkError`)마다. 세션 안에서 여러 번 나올 수 있다 | 세션의 **첫** `onPairingError`에서 1회만 |
| `DISCONNECTED` | `onLinkDown` | `onLinkLost`, 그리고 세션의 두 번째 이후 `onPairingError` |

스택 콜백 이름은 백엔드마다 다르다(alpha: `onLinkUp/onLinkError/onLinkDown`, beta: `onLinkUp/onSecureLinkUp/onPairingError/onLinkLost`).

## 실기기·로그

이 서비스의 증상은 실기기에서만 난다. 스택 동작의 SoT는 각 백엔드 모듈의 번역 규칙이고, 실기기 재현 로그는 `logs/`에 둔다 — **현재 alpha 로그만 확보됨**(`logs/alpha.log`, 스택 raw 콜백 기록). beta 실기기 로그는 아직 없다.

- 로그 재생: `python3 tools/replay.py --backend alpha logs/alpha.log` — 로그의 raw 콜백을 해당 백엔드 번역기에 넣고, 나온 `Event`와 `cleanup()` 호출 횟수를 출력한다. 로그의 백엔드 열과 `--backend`가 다르면 거부한다(콜백 이름이 다르므로).
- 시뮬레이션: `python3 tools/simulate.py --backend beta --failures 3` — 로그 없이 "한 세션에서 페어링 실패 N회" 콜백 열을 만들어 같은 경로로 돌린다.
- 둘 다 `--threshold N`으로 `Recovery`의 임계를 코드 수정 없이 바꿔 볼 수 있다.

## 오라클

- 테스트: `python3 -m unittest discover -s tests -t .`
MD

cat > core/events.py <<'PY'
from dataclasses import dataclass

BONDED = "BONDED"
FAILED = "FAILED"
DISCONNECTED = "DISCONNECTED"


@dataclass(frozen=True)
class Event:
    kind: str
    status: int = 0

    def __str__(self) -> str:
        return f"{self.kind}({self.status})" if self.kind == FAILED else self.kind
PY

cat > core/recovery.py <<'PY'
"""Backend-agnostic pairing recovery.

Counts FAILED events; at FAILURE_THRESHOLD it calls cleanup() which tears the
session down. BONDED resets the counter. DISCONNECTED is ignored.
"""
from core.events import BONDED, FAILED, Event

FAILURE_THRESHOLD = 1


class Recovery:
    def __init__(self, threshold: int = FAILURE_THRESHOLD, on_cleanup=None):
        self.threshold = threshold
        self.failures = 0
        self.cleanups = 0
        self._on_cleanup = on_cleanup

    def on_event(self, event: Event) -> None:
        if event.kind == BONDED:
            self.failures = 0
        elif event.kind == FAILED:
            self.failures += 1
            if self.failures >= self.threshold:
                self.cleanup()

    def cleanup(self) -> None:
        self.cleanups += 1
        self.failures = 0
        if self._on_cleanup is not None:
            self._on_cleanup()
PY

cat > backends/alpha.py <<'PY'
"""Vendor-A pairing stack adapter.

Alpha bonds at link level: onLinkUp means the peer is paired. Every failed
attempt comes back as onLinkError(status) and the stack keeps retrying inside
the same session, so several onLinkError callbacks per session are normal.
"""
from core.events import BONDED, DISCONNECTED, FAILED, Event


class AlphaBackend:
    name = "alpha"

    def __init__(self, sink):
        self._sink = sink

    def start_session(self) -> None:
        pass

    def on_link_up(self) -> None:
        self._sink(Event(BONDED))

    def on_link_error(self, status: int) -> None:
        self._sink(Event(FAILED, status))

    def on_link_down(self) -> None:
        self._sink(Event(DISCONNECTED))

    # raw callback name -> handler, used by tools/ to drive from logs
    def callback(self, name: str, **kw) -> None:
        handlers = {
            "onLinkUp": lambda: self.on_link_up(),
            "onLinkError": lambda: self.on_link_error(int(kw.get("status", 0))),
            "onLinkDown": lambda: self.on_link_down(),
        }
        if name not in handlers:
            raise ValueError(f"alpha: unknown callback {name!r}")
        handlers[name]()
PY

cat > backends/beta.py <<'PY'
"""Vendor-B pairing stack adapter.

Beta bonds only once the encrypted link is up (onSecureLinkUp); a plain
onLinkUp is not a bond. The stack reports a pairing error once per session
(onPairingError); later retries in the same session do not re-raise the error,
they surface as a lost link.
"""
from core.events import BONDED, DISCONNECTED, FAILED, Event


class BetaBackend:
    name = "beta"

    def __init__(self, sink):
        self._sink = sink
        self._reported = False

    def start_session(self) -> None:
        self._reported = False

    def on_link_up(self) -> None:
        # link without encryption is not a bond on this stack
        pass

    def on_secure_link_up(self) -> None:
        self._sink(Event(BONDED))

    def on_pairing_error(self, status: int) -> None:
        if self._reported:
            self._sink(Event(DISCONNECTED))
            return
        self._reported = True
        self._sink(Event(FAILED, status))

    def on_link_lost(self) -> None:
        self._sink(Event(DISCONNECTED))

    def callback(self, name: str, **kw) -> None:
        handlers = {
            "onLinkUp": lambda: self.on_link_up(),
            "onSecureLinkUp": lambda: self.on_secure_link_up(),
            "onPairingError": lambda: self.on_pairing_error(int(kw.get("status", 0))),
            "onLinkLost": lambda: self.on_link_lost(),
        }
        if name not in handlers:
            raise ValueError(f"beta: unknown callback {name!r}")
        handlers[name]()
PY

cat > tools/__init__.py <<'PY'
PY

cat > tools/_run.py <<'PY'
from backends.alpha import AlphaBackend
from backends.beta import BetaBackend
from core.recovery import FAILURE_THRESHOLD, Recovery

BACKENDS = {"alpha": AlphaBackend, "beta": BetaBackend}


def run(backend_name: str, callbacks, threshold=None) -> Recovery:
    """callbacks: iterable of (session, name, kwargs). Prints events and cleanups."""
    recovery = Recovery(threshold=FAILURE_THRESHOLD if threshold is None else threshold)
    events = []

    def sink(event):
        events.append(event)
        recovery.on_event(event)
        print(f"  {event}  -> failures={recovery.failures} cleanups={recovery.cleanups}")

    backend = BACKENDS[backend_name](sink)
    current = None
    for session, name, kw in callbacks:
        if session != current:
            current = session
            backend.start_session()
            print(f"session {session}")
        print(f"  [{name}{' ' + ' '.join(f'{k}={v}' for k, v in kw.items()) if kw else ''}]")
        backend.callback(name, **kw)
    failed = sum(1 for e in events if e.kind == "FAILED")
    print(f"backend={backend_name} threshold={recovery.threshold} "
          f"FAILED_events={failed} cleanups={recovery.cleanups}")
    return recovery
PY

cat > tools/replay.py <<'PY'
#!/usr/bin/env python3
"""Replay a raw stack-callback log through a backend adapter and Recovery.

usage: python3 tools/replay.py --backend alpha|beta [--threshold N] logs/<file>

Log line format: <timestamp> <backend> session=<n> <callback> [key=value ...]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tools._run import run  # noqa: E402


def parse_log(path: str, backend: str):
    out = []
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            ts, log_backend, session_kv, name, *rest = line.split()
            if log_backend != backend:
                sys.exit(f"replay: {path} is a {log_backend} log; --backend {backend} "
                         f"cannot consume it (callback names differ)")
            session = int(session_kv.split("=", 1)[1])
            kw = dict(part.split("=", 1) for part in rest)
            out.append((session, name, kw))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", choices=["alpha", "beta"], required=True)
    ap.add_argument("--threshold", type=int, default=None)
    ap.add_argument("log")
    args = ap.parse_args()
    run(args.backend, parse_log(args.log, args.backend), args.threshold)


if __name__ == "__main__":
    main()
PY

cat > tools/simulate.py <<'PY'
#!/usr/bin/env python3
"""Simulate one pairing session with N failed attempts on a backend, no log needed.

usage: python3 tools/simulate.py --backend alpha|beta --failures N [--threshold N] [--then-bond]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tools._run import run  # noqa: E402

FAIL_CALLBACK = {"alpha": "onLinkError", "beta": "onPairingError"}
BOND_CALLBACKS = {"alpha": ["onLinkUp"], "beta": ["onLinkUp", "onSecureLinkUp"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", choices=["alpha", "beta"], required=True)
    ap.add_argument("--failures", type=int, default=1)
    ap.add_argument("--threshold", type=int, default=None)
    ap.add_argument("--then-bond", action="store_true", help="succeed after the failures")
    args = ap.parse_args()
    callbacks = [(1, FAIL_CALLBACK[args.backend], {"status": "19"}) for _ in range(args.failures)]
    if args.then_bond:
        callbacks += [(1, name, {}) for name in BOND_CALLBACKS[args.backend]]
    run(args.backend, callbacks, args.threshold)


if __name__ == "__main__":
    main()
PY
chmod +x tools/replay.py tools/simulate.py

cat > logs/alpha.log <<'LOG'
# device: A-2213 (vendor-A stack fw 3.4.1), captured 2026-09-12, one pairing session against an unpaired peer
2026-09-12T10:03:11.204 alpha session=1 onLinkError status=19
2026-09-12T10:03:12.911 alpha session=1 onLinkError status=19
2026-09-12T10:03:14.602 alpha session=1 onLinkError status=19
2026-09-12T10:03:16.318 alpha session=1 onLinkError status=19
2026-09-12T10:03:18.007 alpha session=1 onLinkError status=19
2026-09-12T10:03:18.250 alpha session=1 onLinkDown
LOG

cat > tests/test_alpha.py <<'PY'
import unittest

from backends.alpha import AlphaBackend
from core.events import BONDED, DISCONNECTED, FAILED, Event


class AlphaBackendTest(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.backend = AlphaBackend(self.events.append)
        self.backend.start_session()

    def test_link_up_is_bonded(self):
        self.backend.on_link_up()
        self.assertEqual(self.events, [Event(BONDED)])

    def test_every_link_error_is_failed(self):
        for _ in range(3):
            self.backend.on_link_error(19)
        self.assertEqual(self.events, [Event(FAILED, 19)] * 3)

    def test_link_down_is_disconnected(self):
        self.backend.on_link_down()
        self.assertEqual(self.events, [Event(DISCONNECTED)])

    def test_callback_dispatch(self):
        self.backend.callback("onLinkError", status="8")
        self.assertEqual(self.events, [Event(FAILED, 8)])
PY

cat > tests/test_beta.py <<'PY'
import unittest

from backends.beta import BetaBackend
from core.events import BONDED, DISCONNECTED, FAILED, Event


class BetaBackendTest(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.backend = BetaBackend(self.events.append)
        self.backend.start_session()

    def test_link_up_alone_is_not_bonded(self):
        self.backend.on_link_up()
        self.assertEqual(self.events, [])

    def test_secure_link_up_is_bonded(self):
        self.backend.on_link_up()
        self.backend.on_secure_link_up()
        self.assertEqual(self.events, [Event(BONDED)])

    def test_pairing_error_reported_once_per_session(self):
        for _ in range(3):
            self.backend.on_pairing_error(19)
        self.assertEqual(self.events, [Event(FAILED, 19), Event(DISCONNECTED), Event(DISCONNECTED)])

    def test_new_session_reports_again(self):
        self.backend.on_pairing_error(19)
        self.backend.start_session()
        self.backend.on_pairing_error(19)
        self.assertEqual(self.events, [Event(FAILED, 19), Event(FAILED, 19)])

    def test_link_lost_is_disconnected(self):
        self.backend.on_link_lost()
        self.assertEqual(self.events, [Event(DISCONNECTED)])
PY

cat > tests/test_recovery.py <<'PY'
import unittest

from core.events import BONDED, DISCONNECTED, FAILED, Event
from core.recovery import FAILURE_THRESHOLD, Recovery


class RecoveryTest(unittest.TestCase):
    def test_default_threshold_is_one(self):
        self.assertEqual(FAILURE_THRESHOLD, 1)

    def test_cleanup_at_threshold(self):
        calls = []
        r = Recovery(on_cleanup=lambda: calls.append(1))
        r.on_event(Event(FAILED, 19))
        self.assertEqual(r.cleanups, 1)
        self.assertEqual(calls, [1])
        self.assertEqual(r.failures, 0)

    def test_bonded_resets_counter(self):
        r = Recovery(threshold=3)
        r.on_event(Event(FAILED, 19))
        r.on_event(Event(FAILED, 19))
        r.on_event(Event(BONDED))
        self.assertEqual(r.failures, 0)
        self.assertEqual(r.cleanups, 0)

    def test_disconnected_is_ignored(self):
        r = Recovery(threshold=2)
        r.on_event(Event(FAILED, 19))
        r.on_event(Event(DISCONNECTED))
        r.on_event(Event(DISCONNECTED))
        self.assertEqual(r.failures, 1)
        self.assertEqual(r.cleanups, 0)

    def test_counts_up_to_custom_threshold(self):
        r = Recovery(threshold=2)
        r.on_event(Event(FAILED, 19))
        self.assertEqual(r.cleanups, 0)
        r.on_event(Event(FAILED, 19))
        self.assertEqual(r.cleanups, 1)
PY

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "pairsvc: two pairing backends + shared recovery"
