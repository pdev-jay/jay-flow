#!/usr/bin/env bash
# jay-flow eval fixture (plan): public Enum(Event)을 4곳이 exhaustive 분기(else: assert_never)로 소비하고,
# 구 예외 타입 BleError를 lib·service·consumers·sample·통합 테스트가 두루 참조하는 저장소. 전부 green.
set -euo pipefail
mkdir -p lib consumers service sample tests tools
: > lib/__init__.py
: > consumers/__init__.py
: > service/__init__.py
: > sample/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# blecore

BLE 세션 라이브러리(`lib/`)와 그 소비자들. Python 3.9+ 표준 라이브러리만 쓴다.

레이아웃:
- `lib/` — 공개 API. `lib/events.py`의 `Event`, `lib/errors.py`의 `BleError`, `lib/result.py`의 세션 함수들. `lib/failure.py`는 typed failure 자리(아직 비어 있음).
- `service/` — 세션·재연결 서비스. `lib`만 의존.
- `consumers/` — 이벤트 소비자 A/B. `lib`만 의존.
- `sample/` — **공개 API 소비자 예제. CI에 포함된다**(`tools/check_exhaustive.py` 대상이고 `tests/test_sample.py`가 실행한다). 외부 사용자가 복사해 가는 코드이므로 공개 API와 항상 같이 움직여야 한다.
- `tests/test_wiring.py` — 플랫폼 팀이 관리하는 wiring 통합 테스트. lib의 공개 계약이 바뀌면 같이 갱신한다.

계약:
- `Event`는 공개 Enum이다. 소비자는 `Event` 분기를 exhaustive하게 다루고 마지막 `else`에서 `assert_never(event)`를 부른다. 멤버가 늘면 소비자 분기도 늘어야 한다 — `tools/check_exhaustive.py`가 AST로 검사한다.
- 세션 함수는 실패를 `BleError(code, message)`로 알린다(raise 또는 반환). `BleError`는 `(code, message)` 동등성을 가진다.

오라클:
```
python3 -m unittest discover -s tests -t . && python3 tools/check_exhaustive.py
```
MD

cat > lib/_typing.py <<'PY'
"""assert_never — typing.assert_never는 3.11+라 3.9 호환 폴백을 둔다."""
try:
    from typing import assert_never  # type: ignore[attr-defined]
except ImportError:  # pragma: no cover
    def assert_never(value):
        raise AssertionError(f"unhandled value: {value!r}")
PY

cat > lib/events.py <<'PY'
from enum import Enum


class Event(Enum):
    CONNECTED = "connected"
    DISCONNECTED = "disconnected"
    DATA = "data"
PY

cat > lib/errors.py <<'PY'
class BleError(Exception):
    """구 에러 타입. code는 "E_ADDR" 같은 문자열, message는 사람용."""

    def __init__(self, code: str, message: str):
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message

    def __eq__(self, other):
        return isinstance(other, BleError) and (self.code, self.message) == (other.code, other.message)

    def __hash__(self):
        return hash((self.code, self.message))
PY

cat > lib/failure.py <<'PY'
"""typed failure 자리. 아직 비어 있다."""
PY

cat > lib/result.py <<'PY'
import re
from typing import Optional

from lib.errors import BleError

_ADDR = re.compile(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$")


def connect(address: str) -> str:
    """세션 핸들을 돌려준다. 주소가 나쁘면 BleError를 던진다."""
    if not _ADDR.match(address):
        raise BleError("E_ADDR", f"malformed address {address!r}")
    return f"session:{address}"


def try_connect(address: str) -> Optional[BleError]:
    """connect의 비예외 버전: 실패면 BleError를 반환, 성공이면 None."""
    try:
        connect(address)
    except BleError as err:
        return err
    return None


def read_value(handle: str, characteristic: str) -> bytes:
    if not handle.startswith("session:"):
        raise BleError("E_HANDLE", f"not a session handle {handle!r}")
    if characteristic != "2a37":
        raise BleError("E_CHAR", f"unknown characteristic {characteristic}")
    return b"\x00\x48"


def disconnect(handle: str) -> None:
    if not handle.startswith("session:"):
        raise BleError("E_HANDLE", f"not a session handle {handle!r}")
PY

cat > consumers/a.py <<'PY'
from lib._typing import assert_never
from lib.errors import BleError
from lib.events import Event
from lib.result import read_value

_seen = []


def handle(event: Event, handle: str) -> str:
    if event is Event.CONNECTED:
        _seen.append("up")
        return "a:up"
    elif event is Event.DISCONNECTED:
        _seen.append("down")
        return "a:down"
    elif event is Event.DATA:
        try:
            return "a:" + read_value(handle, "2a37").hex()
        except BleError as err:
            return f"a:error:{err.code}"
    else:
        assert_never(event)
PY

cat > consumers/b.py <<'PY'
from lib._typing import assert_never
from lib.errors import BleError
from lib.events import Event
from lib.result import disconnect


def handle(event: Event, handle: str) -> str:
    if event is Event.CONNECTED:
        return "b:ready"
    elif event is Event.DATA:
        return "b:data"
    elif event is Event.DISCONNECTED:
        try:
            disconnect(handle)
        except BleError as err:
            return f"b:error:{err.code}"
        return "b:closed"
    else:
        assert_never(event)
PY

cat > service/session.py <<'PY'
from typing import Optional, Union

from lib.errors import BleError
from lib.result import connect, try_connect


class Session:
    def __init__(self) -> None:
        self.handle: Optional[str] = None
        self.last_error: Optional[BleError] = None

    def open(self, address: str) -> Union[str, BleError]:
        outcome = try_connect(address)
        if isinstance(outcome, BleError):
            self.last_error = outcome
            return outcome
        self.handle = connect(address)
        return self.handle

    def is_failed(self) -> bool:
        return isinstance(self.last_error, BleError)
PY

cat > service/reconnect.py <<'PY'
from lib._typing import assert_never
from lib.errors import BleError
from lib.events import Event
from lib.result import connect


def should_reconnect(event: Event) -> bool:
    if event is Event.DISCONNECTED:
        return True
    elif event is Event.CONNECTED:
        return False
    elif event is Event.DATA:
        return False
    else:
        assert_never(event)


def reconnect(address: str, attempts: int = 3) -> str:
    last: BleError = BleError("E_NONE", "no attempts")
    for _ in range(attempts):
        try:
            return connect(address)
        except BleError as err:
            last = err
    raise last
PY

cat > sample/app.py <<'PY'
"""공개 API 소비자 예제. 외부 사용자가 이 파일을 그대로 복사해 시작한다."""
from lib._typing import assert_never
from lib.errors import BleError
from lib.events import Event
from lib.result import connect, read_value


def on_event(event: Event, handle: str) -> str:
    if event is Event.CONNECTED:
        return "sample: connected"
    elif event is Event.DISCONNECTED:
        return "sample: disconnected"
    elif event is Event.DATA:
        return "sample: " + read_value(handle, "2a37").hex()
    else:
        assert_never(event)


def main(address: str = "C4:7C:8D:65:A1:02") -> str:
    try:
        handle = connect(address)
    except BleError as err:
        return f"sample: failed {err.code}"
    return on_event(Event.CONNECTED, handle)
PY

cat > tools/check_exhaustive.py <<'PY'
"""Event 분기의 exhaustive 검사.

대상 파일의 각 if/elif 체인 중 마지막 else가 assert_never(...)를 부르는 것을 찾아,
비교된 Event 멤버 집합이 Event의 전체 멤버와 같은지 본다. 빠진 멤버가 있으면 exit 1.
사용: python3 tools/check_exhaustive.py [files...]   (기본: consumers/*.py service/*.py sample/*.py)
"""
import ast
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lib.events import Event  # noqa: E402

DEFAULT_GLOBS = ["consumers/*.py", "service/*.py", "sample/*.py"]


def _members_in(test):
    out = set()
    for node in ast.walk(test):
        if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id == "Event":
            out.add(node.attr)
    return out


def _calls_assert_never(stmts):
    for s in stmts:
        for node in ast.walk(s):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "assert_never":
                return True
    return False


def _chains(tree):
    """if/elif 체인의 (head, [tests]) 목록. elif는 AST상 orelse 안의 If라 head에서만 시작한다."""
    elif_nodes = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.If) and len(node.orelse) == 1 and isinstance(node.orelse[0], ast.If):
            elif_nodes.add(id(node.orelse[0]))
    for node in ast.walk(tree):
        if not isinstance(node, ast.If) or id(node) in elif_nodes:
            continue
        tests = [node.test]
        cur = node
        while len(cur.orelse) == 1 and isinstance(cur.orelse[0], ast.If):
            cur = cur.orelse[0]
            tests.append(cur.test)
        if cur.orelse and _calls_assert_never(cur.orelse):
            yield node, tests


def check_file(path):
    with open(path, encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), path)
    expected = {m.name for m in Event}
    problems = []
    seen_chain = False
    for head, tests in _chains(tree):
        covered = set()
        for t in tests:
            covered |= _members_in(t)
        if not covered:
            continue
        seen_chain = True
        missing = expected - covered
        if missing:
            problems.append(f"{path}:{head.lineno} missing Event members: {sorted(missing)}")
    return seen_chain, problems


def main(argv):
    files = argv[1:] or sorted(f for g in DEFAULT_GLOBS for f in glob.glob(g))
    problems = []
    checked = 0
    for path in files:
        seen, probs = check_file(path)
        if seen:
            checked += 1
        problems.extend(probs)
    for p in problems:
        print(p)
    print(f"exhaustive check: {checked} file(s) with Event branches, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

cat > tests/test_events.py <<'PY'
import unittest

from lib.events import Event


class EventTest(unittest.TestCase):
    def test_members(self):
        self.assertEqual([e.name for e in Event], ["CONNECTED", "DISCONNECTED", "DATA"])
PY

cat > tests/test_result.py <<'PY'
import unittest

from lib.errors import BleError
from lib.result import connect, read_value, try_connect


class ResultTest(unittest.TestCase):
    def test_connect_ok(self):
        self.assertEqual(connect("C4:7C:8D:65:A1:02"), "session:C4:7C:8D:65:A1:02")

    def test_connect_bad_address_raises(self):
        with self.assertRaises(BleError) as ctx:
            connect("nope")
        self.assertEqual(ctx.exception.code, "E_ADDR")

    def test_try_connect_returns_error(self):
        self.assertIsInstance(try_connect("nope"), BleError)
        self.assertIsNone(try_connect("C4:7C:8D:65:A1:02"))

    def test_read_value_unknown_characteristic(self):
        with self.assertRaises(BleError):
            read_value("session:x", "ffff")
PY

cat > tests/test_consumers.py <<'PY'
import unittest

from consumers import a, b
from lib.events import Event


class ConsumerTest(unittest.TestCase):
    def test_a_dispatch(self):
        self.assertEqual(a.handle(Event.CONNECTED, "session:x"), "a:up")
        self.assertEqual(a.handle(Event.DATA, "session:x"), "a:0048")
        self.assertEqual(a.handle(Event.DATA, "bogus"), "a:error:E_HANDLE")

    def test_b_dispatch(self):
        self.assertEqual(b.handle(Event.DISCONNECTED, "session:x"), "b:closed")
        self.assertEqual(b.handle(Event.DISCONNECTED, "bogus"), "b:error:E_HANDLE")
PY

cat > tests/test_service.py <<'PY'
import unittest

from lib.errors import BleError
from lib.events import Event
from service.reconnect import reconnect, should_reconnect
from service.session import Session


class ServiceTest(unittest.TestCase):
    def test_session_open_failure_records_error(self):
        s = Session()
        out = s.open("bad")
        self.assertIsInstance(out, BleError)
        self.assertTrue(s.is_failed())

    def test_reconnect_raises_last(self):
        with self.assertRaises(BleError):
            reconnect("bad", attempts=2)

    def test_should_reconnect(self):
        self.assertTrue(should_reconnect(Event.DISCONNECTED))
        self.assertFalse(should_reconnect(Event.DATA))
PY

cat > tests/test_wiring.py <<'PY'
"""wiring 통합 테스트 — 플랫폼 팀 소유. service ↔ lib 배선이 공개 계약대로 붙어 있는지 본다.
lib 공개 계약이 바뀌면 이 파일도 같이 갱신해야 한다(README 참고)."""
import unittest

from lib.errors import BleError
from service.session import Session


class WiringTest(unittest.TestCase):
    def test_session_surfaces_exact_lib_error(self):
        s = Session()
        out = s.open("bad")
        self.assertEqual(out, BleError("E_ADDR", "malformed address 'bad'"))
        self.assertEqual(s.last_error, BleError("E_ADDR", "malformed address 'bad'"))

    def test_session_open_ok(self):
        s = Session()
        self.assertEqual(s.open("C4:7C:8D:65:A1:02"), "session:C4:7C:8D:65:A1:02")
PY

cat > tests/test_sample.py <<'PY'
import unittest

from sample.app import main, on_event
from lib.events import Event


class SampleTest(unittest.TestCase):
    def test_main_happy(self):
        self.assertEqual(main(), "sample: connected")

    def test_main_failure(self):
        self.assertEqual(main("bad"), "sample: failed E_ADDR")

    def test_on_event_data(self):
        self.assertEqual(on_event(Event.DATA, "session:x"), "sample: 0048")
PY

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "blecore: lib + service + consumers + sample, exhaustive check tool"
