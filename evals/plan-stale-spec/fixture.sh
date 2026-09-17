#!/usr/bin/env bash
# jay-flow eval fixture (plan, hard): BLE 페어링 클라이언트의 링크 복구 계층 + 날짜가 다른 기기 사양 사본 2개 + 실기기 로그.
# 함정: docs/device/protocol_2026-06.md(옛 사본: 인증 실패 후 재광고 없음, 최대 페어 1)와
#       docs/device/protocol_latest.md(최신: 250ms 백오프 뒤 재광고, 최대 페어 2). 로그는 최신 사양대로 움직인다.
set -euo pipefail
mkdir -p client docs/device logs tools tests
: > client/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# pairing-client

BLE 기기와의 링크 복구 계층(폰 쪽). 기기 이벤트 스트림(광고/연결/절단 status)을 받아 링크 상태를 굴리고,
연결 실패가 쌓이면 로컬 상태를 정리한다.

계약:
- 본드 삭제 후 복구는 기기 재광고를 전제로 한다 — 클라이언트는 기기가 다시 광고할 때 재연결한다.
- 연결 실패 status는 `client/recovery.py`가 받아 세고, 임계에 도달하면 `cleanup()`을 호출한다.
- 링크 상태 전이는 `client/link.py`가 담당한다. recovery는 링크를 직접 열지 않는다.

이 증상은 실기기에서만 난다. 기기 동작의 SoT는 `docs/device/` 최신본, 실기기 로그는 `logs/`.

재생: `python3 tools/replay.py logs/device_01.log` (옵션 `--threshold N`)
테스트: `python3 -m unittest discover -s tests -t .`
MD

cat > docs/device/protocol_2026-06.md <<'MD'
# Device link protocol (2026-06 사본)

fw 2.2.x 기준. 폰 앱 팀 공유용으로 2026-06에 복사한 사본.

## Advertising
- 전원 인가 후 연결 가능 광고(interval 100ms).
- 연결이 맺어지면 광고를 멈춘다.

## Pairing / bonding
- 최대 페어(bonded peer) 수: **1**.
- 슬롯이 차 있으면 새 페어링 요청은 거절된다. 슬롯을 비우려면 기기 버튼 3초 → 페어링 모드.

## Auth failure
- 암호화 개시 중 키 불일치/키 없음이면 기기는 status `0x05`(Authentication Failure)로 링크를 절단한다.
- 절단 후 기기는 **재광고하지 않는다**. 사용자가 기기 버튼을 눌러 페어링 모드로 진입해야 다시 광고한다.

## Disconnect status codes
| status | 의미 |
|---|---|
| 0x05 | Authentication Failure |
| 0x08 | Connection Timeout |
| 0x13 | Remote User Terminated |
MD

cat > docs/device/protocol_latest.md <<'MD'
# Device link protocol (latest)

## 변경 이력
| 날짜 | fw | 변경 |
|---|---|---|
| 2026-08 | 2.3.0 | 인증 실패 후 재광고 정책 변경 — 절단 후 250ms 백오프 뒤 재광고. 최대 페어 1 → 2 |
| 2026-06 | 2.2.1 | 초판 |

## Advertising
- 전원 인가 후 연결 가능 광고(interval 100ms).
- 연결이 맺어지면 광고를 멈춘다. 절단되면(사유 불문) 250ms 백오프 뒤 광고를 재개한다.

## Pairing / bonding
- 최대 페어(bonded peer) 수: **2**.
- 슬롯이 남아 있으면 새 페어링 요청을 받는다. 둘 다 차 있으면 거절(기기 버튼 3초로 전체 삭제).
- 기기는 폰 쪽 본드 삭제를 알 수 없다. 폰이 본드를 지워도 기기 슬롯의 키는 남는다.

## Auth failure
- 암호화 개시 중 키 불일치/키 없음이면 기기는 status `0x05`(Authentication Failure)로 링크를 절단한다.
- 절단 후 **250ms 백오프 뒤 재광고**한다. 기존 슬롯의 키는 유지된다.
- 같은 피어가 새 페어링(bonding) 요청을 보내면 남은 슬롯에 새 키를 저장한다.

## Disconnect status codes
| status | 의미 |
|---|---|
| 0x05 | Authentication Failure |
| 0x08 | Connection Timeout |
| 0x13 | Remote User Terminated |
MD

cat > client/link.py <<'PY'
"""Link state machine fed by device events (mirrors the phone-side BLE stack).

Events come from the platform stack in the order the device produced them:
    adv           device advertisement seen while scanning
    connected     link established, encryption requested with the stored key
    disconnect    link dropped; `status` is the HCI reason code (0 = local close)
"""
from dataclasses import dataclass

IDLE = "idle"
CONNECTING = "connecting"
CONNECTED = "connected"
DISCONNECTED = "disconnected"


@dataclass(frozen=True)
class Event:
    t_ms: int
    kind: str
    status: int = 0


class Link:
    def __init__(self, on_status):
        self.state = IDLE
        self.connects = 0
        self._on_status = on_status

    @property
    def reconnects(self) -> int:
        """Connect attempts after the first one."""
        return max(self.connects - 1, 0)

    def feed(self, ev: Event) -> None:
        if ev.kind == "adv":
            if self.state in (IDLE, DISCONNECTED):
                self.state = CONNECTING
                self.connects += 1
        elif ev.kind == "connected":
            self.state = CONNECTED
        elif ev.kind == "disconnect":
            self.state = DISCONNECTED
            self._on_status(ev.status)
        else:
            raise ValueError(f"unknown event kind: {ev.kind!r}")

    def reset(self) -> None:
        """Forget the current link. The next advertisement starts a fresh connect."""
        self.state = IDLE
PY

cat > client/recovery.py <<'PY'
"""Connection-failure recovery.

Receives the disconnect status from the link, counts consecutive failures and
calls `cleanup()` when the count reaches `threshold`.
"""

STATUS_OK = 0x00
STATUS_AUTH_FAILURE = 0x05
STATUS_TIMEOUT = 0x08
STATUS_REMOTE_TERMINATED = 0x13


class Recovery:
    def __init__(self, link, threshold: int = 1):
        self.link = link
        self.threshold = threshold
        self.fail_count = 0
        self.cleanup_calls = 0

    def on_status(self, status: int) -> None:
        if status == STATUS_OK:
            self.fail_count = 0
            return
        self.fail_count += 1
        if self.fail_count >= self.threshold:
            self.cleanup()

    def cleanup(self) -> None:
        """Drop local link state so the next advertisement starts a clean connect."""
        self.cleanup_calls += 1
        self.fail_count = 0
        self.link.reset()
PY

cat > logs/device_01.log <<'LOG'
# device_01  fw 2.3.0  captured 2026-09-14  (phone: bond removed in system settings at 10:31:58)
2026-09-14T10:31:58.000 note bond-removed local
2026-09-14T10:32:01.000 adv rssi=-61
2026-09-14T10:32:01.120 connected
2026-09-14T10:32:01.410 disconnect status=5
2026-09-14T10:32:01.660 adv rssi=-60
2026-09-14T10:32:01.790 connected
2026-09-14T10:32:02.070 disconnect status=5
2026-09-14T10:32:02.320 adv rssi=-61
2026-09-14T10:32:02.450 connected
2026-09-14T10:32:02.740 disconnect status=5
2026-09-14T10:32:02.990 adv rssi=-62
2026-09-14T10:32:03.110 connected
2026-09-14T10:32:03.400 disconnect status=5
2026-09-14T10:32:03.650 adv rssi=-61
2026-09-14T10:32:03.780 connected
2026-09-14T10:32:04.060 disconnect status=5
2026-09-14T10:32:04.310 adv rssi=-60
2026-09-14T10:32:04.440 connected
2026-09-14T10:32:04.730 disconnect status=5
2026-09-14T10:32:04.980 adv rssi=-61
2026-09-14T10:32:05.100 connected
2026-09-14T10:32:05.390 disconnect status=5
2026-09-14T10:32:05.640 adv rssi=-61
LOG

cat > tools/replay.py <<'PY'
"""Replay a device log through Link + Recovery and print what the client did.

usage: python3 tools/replay.py logs/device_01.log [--threshold N]
"""
import argparse
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from client.link import Event, Link  # noqa: E402
from client.recovery import Recovery  # noqa: E402


def parse(path):
    events = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            ts, kind, *rest = line.split()
            if kind == "note":
                continue
            status = 0
            for tok in rest:
                if tok.startswith("status="):
                    status = int(tok.split("=", 1)[1])
            t_ms = int(datetime.fromisoformat(ts).timestamp() * 1000)
            events.append(Event(t_ms, kind, status))
    return events


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--threshold", type=int, default=1)
    args = ap.parse_args()

    events = parse(args.log)
    link = Link(on_status=lambda s: None)
    recovery = Recovery(link, threshold=args.threshold)
    link._on_status = recovery.on_status

    t0 = events[0].t_ms
    last_cleanup = None
    cleanups_before = 0
    for ev in events:
        link.feed(ev)
        if recovery.cleanup_calls > cleanups_before:
            cleanups_before = recovery.cleanup_calls
            last_cleanup = ev.t_ms
        if ev.kind == "adv" and last_cleanup is not None and link.state == "connecting":
            print(f"  cleanup #{cleanups_before} at +{last_cleanup - t0}ms "
                  f"-> reconnect at +{ev.t_ms - t0}ms (+{ev.t_ms - last_cleanup}ms)")
            last_cleanup = None

    statuses = sorted({e.status for e in events if e.kind == "disconnect"})
    print(f"events: {len(events)}  threshold: {args.threshold}")
    print(f"disconnects: {sum(1 for e in events if e.kind == 'disconnect')}  status codes: {statuses}")
    print(f"cleanup calls: {recovery.cleanup_calls}")
    print(f"reconnects: {link.reconnects}")
    print(f"final state: {link.state}")


if __name__ == "__main__":
    main()
PY

cat > tests/test_recovery.py <<'PY'
import unittest

from client.link import Link
from client.recovery import STATUS_AUTH_FAILURE, STATUS_OK, STATUS_TIMEOUT, Recovery


def make(threshold=1):
    link = Link(on_status=lambda s: None)
    rec = Recovery(link, threshold=threshold)
    link._on_status = rec.on_status
    return link, rec


class RecoveryTest(unittest.TestCase):
    def test_cleanup_on_first_failure(self):
        _, rec = make(threshold=1)
        rec.on_status(STATUS_AUTH_FAILURE)
        self.assertEqual(rec.cleanup_calls, 1)
        self.assertEqual(rec.fail_count, 0)

    def test_success_resets_count(self):
        _, rec = make(threshold=2)
        rec.on_status(STATUS_TIMEOUT)
        rec.on_status(STATUS_OK)
        rec.on_status(STATUS_TIMEOUT)
        self.assertEqual(rec.cleanup_calls, 0)

    def test_threshold_two_cleans_on_second(self):
        link, rec = make(threshold=2)
        rec.on_status(STATUS_TIMEOUT)
        self.assertEqual(rec.cleanup_calls, 0)
        rec.on_status(STATUS_TIMEOUT)
        self.assertEqual(rec.cleanup_calls, 1)
        self.assertEqual(link.state, "idle")
PY

cat > tests/test_link.py <<'PY'
import unittest

from client.link import CONNECTED, CONNECTING, DISCONNECTED, IDLE, Event, Link


class LinkTest(unittest.TestCase):
    def test_adv_from_idle_connects(self):
        link = Link(on_status=lambda s: None)
        link.feed(Event(0, "adv"))
        self.assertEqual(link.state, CONNECTING)
        link.feed(Event(100, "connected"))
        self.assertEqual(link.state, CONNECTED)
        self.assertEqual(link.reconnects, 0)

    def test_disconnect_reports_status_and_adv_reconnects(self):
        seen = []
        link = Link(on_status=seen.append)
        link.feed(Event(0, "adv"))
        link.feed(Event(100, "connected"))
        link.feed(Event(400, "disconnect", status=5))
        self.assertEqual(link.state, DISCONNECTED)
        self.assertEqual(seen, [5])
        link.feed(Event(650, "adv"))
        self.assertEqual(link.reconnects, 1)

    def test_reset_returns_to_idle(self):
        link = Link(on_status=lambda s: None)
        link.feed(Event(0, "adv"))
        link.reset()
        self.assertEqual(link.state, IDLE)
PY

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "pairing-client: link recovery with device protocol docs and field log"
