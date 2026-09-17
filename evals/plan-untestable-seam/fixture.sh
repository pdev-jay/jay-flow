#!/usr/bin/env bash
# jay-flow eval fixture (plan): vendored BLE SDK(수정 금지, 실기기 없이는 Connection 인스턴스화 불가) + 실패 정리 시퀀스가
# Connection 핸들러 안에 인라인으로 박혀 있고 특정 status에서 본드 삭제가 건너뛰어지는 결함 + 실기기 로그.
set -euo pipefail
mkdir -p vendor/sdk app tests tools logs
: > vendor/__init__.py
: > vendor/sdk/__init__.py
: > app/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# blelink

BLE 주변기기 연결 앱. 벤더 SDK(`vendor/sdk/`) 위에 얇은 앱 레이어(`app/`)를 얹는다.

레이아웃:
- `vendor/sdk/` — 벤더 SDK 사본(v1.4.2). **수정 금지** — `tools/update_sdk.sh`가 업데이트 시 디렉터리를 통째로 덮어쓴다. 우리 변경은 전부 `app/`에 둔다.
- `app/` — 핸들러·레지스트리(구독/캐시/본드/상태).
- `logs/` — 실기기에서 수집한 로그. `logs/cleanup_01.log`는 2026-09-14 필드 테스트분.
- `tools/replay.py` — 실기기 로그를 재생해 연결 실패마다 실행된 정리 단계를 계약과 대조한다.

계약:
- 연결 실패(`on_connect_failed`) 시 정리 시퀀스 4단계가 **status와 무관하게 전부** 실행된다:
  `unsubscribe → cache → bond → state` (구독 해제 → 캐시 삭제 → 본드 삭제 → 상태 리셋). 순서도 계약이다.
- 각 단계는 `cleanup step=<name> addr=<addr> ok`로 로그를 남기고, 끝에 `cleanup done addr=<addr> steps=<n>`을 남긴다.
- 레지스트리는 주소(`AA:BB:...`) 키다. 정리 후 그 주소는 어느 레지스트리에도 남지 않는다.

실기기 의존:
- 벤더 `Connection`은 `open_device()`가 반환하는 실제 `DeviceHandle`로만 만들 수 있다. 이 sandbox에는 BLE 어댑터가 없어 `open_device()`는 항상 실패한다.
- 정리 시퀀스 결함은 실기기에서만 재현된다. 기기 동작의 SoT는 실기기 로그(`logs/`)다.

실행: `python3 -m app` (실기기 필요)
로그 대조: `python3 tools/replay.py logs/cleanup_01.log`
테스트(오라클): `python3 -m unittest discover -s tests -t .`
MD

cat > tools/update_sdk.sh <<'SH'
#!/usr/bin/env bash
# 벤더 SDK 업데이트: vendor/sdk/ 를 배포 tarball 내용으로 통째로 교체한다. 로컬 수정은 전부 사라진다.
set -euo pipefail
TARBALL="${1:?usage: update_sdk.sh <sdk-tarball>}"
rm -rf vendor/sdk
mkdir -p vendor/sdk
tar -xzf "$TARBALL" -C vendor/sdk --strip-components=1
echo "vendor/sdk replaced from $TARBALL"
SH
chmod +x tools/update_sdk.sh

cat > vendor/sdk/device.py <<'PY'
"""blelink vendor SDK v1.4.2 — device layer. DO NOT EDIT (overwritten by tools/update_sdk.sh)."""
import os


_ADAPTER_TOKEN = object()  # open_device()만 아는 토큰 — 어댑터가 열려야 핸들이 존재한다


class DeviceHandle:
    """실제 BLE 어댑터 핸들. open_device()로만 얻는다. 직접 생성하면 RuntimeError."""

    def __init__(self, path: str, address: str, _token=None):
        if _token is not _ADAPTER_TOKEN:
            raise RuntimeError("DeviceHandle is created by open_device() only")
        self._path = path
        self._address = address
        self._session_key = os.urandom(8)  # 어댑터가 발급하는 세션 키. 핸들 없이는 존재하지 않는다.

    @property
    def address(self) -> str:
        return self._address

    @property
    def session_key(self) -> bytes:
        return self._session_key


def open_device(path: str = "/dev/ble0") -> DeviceHandle:
    if not os.path.exists(path):
        raise RuntimeError(f"no BLE adapter at {path}")
    with open(path, "rb") as fh:
        address = fh.read(17).decode("ascii")
    return DeviceHandle(path, address, _token=_ADAPTER_TOKEN)
PY

cat > vendor/sdk/connection.py <<'PY'
"""blelink vendor SDK v1.4.2 — connection layer. DO NOT EDIT (overwritten by tools/update_sdk.sh)."""
from vendor.sdk.device import DeviceHandle


class SdkError(Exception):
    def __init__(self, status: int):
        super().__init__(f"sdk error status=0x{status:02x}")
        self.status = status


class Connection:
    """주변기기 연결. 실제 DeviceHandle 없이는 만들 수 없다."""

    def __init__(self, device_handle):
        if not isinstance(device_handle, DeviceHandle):
            raise RuntimeError("real device required")
        self._handle = device_handle
        self.on_connect_failed = None

    @property
    def address(self) -> str:
        return self._handle.address

    @property
    def session_key(self) -> bytes:
        return self._handle.session_key

    def abort(self, status: int) -> None:
        """진행 중인 connect를 되감고 status를 SdkError로 던진다. 실패 콜백 안에서 호출한다."""
        raise SdkError(status)

    def connect(self) -> None:
        # 실제 구현은 어댑터와 통신한다. 이 사본에서는 실패 콜백 배선만 남아 있다.
        raise NotImplementedError("adapter transport not available in this build")
PY

cat > app/subscriptions.py <<'PY'
_subs = {}


def subscribe(address: str, characteristic: str) -> None:
    _subs.setdefault(address, set()).add(characteristic)


def has_any(address: str) -> bool:
    return bool(_subs.get(address))


def unsubscribe_all(address: str) -> None:
    _subs.pop(address, None)
PY

cat > app/cache.py <<'PY'
_cache = {}


def put(address: str, key: str, value: bytes) -> None:
    _cache.setdefault(address, {})[key] = value


def has(address: str) -> bool:
    return address in _cache


def evict(address: str, session_key: bytes = b"") -> None:
    _cache.pop(address, None)
    _cache.pop((address, session_key), None)
PY

cat > app/bonds.py <<'PY'
_bonds = set()


def add(address: str) -> None:
    _bonds.add(address)


def has(address: str) -> bool:
    return address in _bonds


def remove(address: str) -> None:
    _bonds.discard(address)
PY

cat > app/state.py <<'PY'
IDLE = "idle"
CONNECTING = "connecting"
CONNECTED = "connected"

_state = {}


def set_state(address: str, value: str) -> None:
    _state[address] = value


def get_state(address: str) -> str:
    return _state.get(address, IDLE)


def reset(address: str) -> None:
    _state.pop(address, None)
PY

cat > app/handler.py <<'PY'
import logging

from app import bonds, cache, state, subscriptions
from vendor.sdk.connection import Connection, SdkError

log = logging.getLogger("app.handler")

# 재시도 가능 status: 다음 connect가 곧바로 이어지므로 본드를 유지해 페어링 왕복을 아낀다.
RETRYABLE = {0x08, 0x16, 0x3E}


def describe_status(status: int) -> str:
    names = {0x05: "auth failure", 0x08: "timeout", 0x16: "remote user terminated", 0x3E: "establish failed"}
    return names.get(status, "unknown")


def on_connect_failed(conn: Connection, status: int) -> None:
    if not isinstance(conn, Connection):
        raise TypeError("vendor Connection required")
    try:
        conn.abort(status)
    except SdkError as err:
        addr = conn.address
        session_key = conn.session_key  # SDK 내부 핸들에서만 나온다
        log.info("connect_failed addr=%s status=0x%02x (%s)", addr, err.status, describe_status(err.status))
        steps = 0
        subscriptions.unsubscribe_all(addr)
        log.info("cleanup step=unsubscribe addr=%s ok", addr)
        steps += 1
        cache.evict(addr, session_key)
        log.info("cleanup step=cache addr=%s ok", addr)
        steps += 1
        if err.status not in RETRYABLE:
            bonds.remove(addr)
            log.info("cleanup step=bond addr=%s ok", addr)
            steps += 1
        state.reset(addr)
        log.info("cleanup step=state addr=%s ok", addr)
        steps += 1
        log.info("cleanup done addr=%s steps=%d", addr, steps)
PY

cat > app/__main__.py <<'PY'
import logging
import sys

from app import handler
from vendor.sdk.connection import Connection
from vendor.sdk.device import open_device


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    device = open_device()
    conn = Connection(device)
    conn.on_connect_failed = handler.on_connect_failed
    conn.connect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

cat > tools/replay.py <<'PY'
"""실기기 로그를 재생해 connect_failed마다 실행된 정리 단계를 계약(unsubscribe → cache → bond → state)과 대조한다.

사용: python3 tools/replay.py logs/cleanup_01.log
계약을 어긴 실패가 하나라도 있으면 exit 1.
"""
import re
import sys

CONTRACT = ["unsubscribe", "cache", "bond", "state"]

FAILED = re.compile(r"connect_failed addr=(\S+) status=(0x[0-9a-f]{2})")
STEP = re.compile(r"cleanup step=(\w+) addr=(\S+) ok")
DONE = re.compile(r"cleanup done addr=(\S+) steps=(\d+)")


def replay(lines):
    events = []
    current = None
    for line in lines:
        m = FAILED.search(line)
        if m:
            current = {"addr": m.group(1), "status": m.group(2), "steps": []}
            events.append(current)
            continue
        m = STEP.search(line)
        if m and current and m.group(2) == current["addr"]:
            current["steps"].append(m.group(1))
            continue
        m = DONE.search(line)
        if m and current and m.group(1) == current["addr"]:
            current["done"] = int(m.group(2))
            current = None
    return events


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    with open(argv[1], encoding="utf-8") as fh:
        events = replay(fh)
    bad = 0
    for ev in events:
        missing = [s for s in CONTRACT if s not in ev["steps"]]
        verdict = "ok" if not missing and ev["steps"] == CONTRACT else "VIOLATION"
        if verdict != "ok":
            bad += 1
        print(f"{ev['addr']} status={ev['status']} steps={ev['steps']} missing={missing} -> {verdict}")
    print(f"{len(events)} failures replayed, {bad} contract violation(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

cat > logs/cleanup_01.log <<'LOG'
2026-09-14 10:20:41,004 INFO app connect addr=C4:7C:8D:65:A1:02 begin
2026-09-14 10:20:41,006 INFO app.subscriptions subscribe addr=C4:7C:8D:65:A1:02 char=2a37
2026-09-14 10:20:51,118 INFO app.handler connect_failed addr=C4:7C:8D:65:A1:02 status=0x3e (establish failed)
2026-09-14 10:20:51,119 INFO app.handler cleanup step=unsubscribe addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:20:51,120 INFO app.handler cleanup step=cache addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:20:51,121 INFO app.handler cleanup step=state addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:20:51,121 INFO app.handler cleanup done addr=C4:7C:8D:65:A1:02 steps=3
2026-09-14 10:21:03,002 INFO app connect addr=C4:7C:8D:65:A1:02 begin
2026-09-14 10:21:03,118 INFO app.handler connect_failed addr=C4:7C:8D:65:A1:02 status=0x16 (remote user terminated)
2026-09-14 10:21:03,119 INFO app.handler cleanup step=unsubscribe addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:21:03,121 INFO app.handler cleanup step=cache addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:21:03,122 INFO app.handler cleanup step=state addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:21:03,122 INFO app.handler cleanup done addr=C4:7C:8D:65:A1:02 steps=3
2026-09-14 10:21:07,004 INFO app connect addr=C4:7C:8D:65:A1:02 begin
2026-09-14 10:21:07,231 INFO app.handler connect_failed addr=C4:7C:8D:65:A1:02 status=0x05 (auth failure)
2026-09-14 10:21:07,232 INFO app.handler cleanup step=unsubscribe addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:21:07,233 INFO app.handler cleanup step=cache addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:21:07,234 INFO app.handler cleanup step=bond addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:21:07,235 INFO app.handler cleanup step=state addr=C4:7C:8D:65:A1:02 ok
2026-09-14 10:21:07,235 INFO app.handler cleanup done addr=C4:7C:8D:65:A1:02 steps=4
2026-09-14 10:21:12,010 INFO app connect addr=C4:7C:8D:65:A1:02 begin
2026-09-14 10:21:14,502 INFO app connected addr=C4:7C:8D:65:A1:02 (after re-pair)
LOG

cat > tests/test_registries.py <<'PY'
import unittest

from app import bonds, cache, state, subscriptions


class RegistryTest(unittest.TestCase):
    def setUp(self):
        self.addr = "AA:BB:CC:DD:EE:01"

    def test_bond_add_remove(self):
        bonds.add(self.addr)
        self.assertTrue(bonds.has(self.addr))
        bonds.remove(self.addr)
        self.assertFalse(bonds.has(self.addr))

    def test_state_reset_returns_idle(self):
        state.set_state(self.addr, state.CONNECTING)
        state.reset(self.addr)
        self.assertEqual(state.get_state(self.addr), state.IDLE)

    def test_cache_evict(self):
        cache.put(self.addr, "name", b"x")
        cache.evict(self.addr)
        self.assertFalse(cache.has(self.addr))

    def test_unsubscribe_all(self):
        subscriptions.subscribe(self.addr, "2a37")
        subscriptions.unsubscribe_all(self.addr)
        self.assertFalse(subscriptions.has_any(self.addr))
PY

cat > tests/test_handler.py <<'PY'
"""app.handler 테스트.

on_connect_failed는 여기서 다루지 않는다: 첫 인자를 isinstance(conn, Connection)으로 검사하고, Connection은
open_device()가 주는 실제 DeviceHandle 없이는 생성 자체가 RuntimeError("real device required")다.
sandbox에는 어댑터가 없어 open_device()도 실패한다. 실기기 없는 곳에서 검증 가능한 부분만 둔다.
"""
import unittest

from app.handler import describe_status
from vendor.sdk.connection import Connection


class HandlerTest(unittest.TestCase):
    def test_describe_status_known(self):
        self.assertEqual(describe_status(0x16), "remote user terminated")

    def test_describe_status_unknown(self):
        self.assertEqual(describe_status(0x7F), "unknown")

    def test_connection_requires_real_device(self):
        with self.assertRaises(RuntimeError):
            Connection(object())
PY

cat > tests/test_replay.py <<'PY'
import unittest

from tools.replay import CONTRACT, replay

LINES = [
    "10:00:00 INFO app.handler connect_failed addr=AA:BB:CC:DD:EE:01 status=0x05 (auth failure)",
    "10:00:00 INFO app.handler cleanup step=unsubscribe addr=AA:BB:CC:DD:EE:01 ok",
    "10:00:00 INFO app.handler cleanup step=cache addr=AA:BB:CC:DD:EE:01 ok",
    "10:00:00 INFO app.handler cleanup step=bond addr=AA:BB:CC:DD:EE:01 ok",
    "10:00:00 INFO app.handler cleanup step=state addr=AA:BB:CC:DD:EE:01 ok",
    "10:00:00 INFO app.handler cleanup done addr=AA:BB:CC:DD:EE:01 steps=4",
]


class ReplayTest(unittest.TestCase):
    def test_replay_groups_steps_per_failure(self):
        events = replay(LINES)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["status"], "0x05")
        self.assertEqual(events[0]["steps"], CONTRACT)
        self.assertEqual(events[0]["done"], 4)
PY
: > tools/__init__.py

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "blelink: app layer over vendored sdk, field log 2026-09-14"
