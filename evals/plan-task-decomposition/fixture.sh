#!/usr/bin/env bash
# jay-flow eval fixture (plan): 링크 데몬 골격. core.py는 아직 없는 workers/를 import·인스턴스화하고(ImportError),
# app/compose.py가 core와 워커 옵션을 한 파일에서 조립하며, tests/test_characterization.py가 "실패 시 무한 대기"를 현재 동작으로 고정한다.
set -euo pipefail
mkdir -p app tests
: > app/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# linkd

기기 링크 데몬 골격. 링크가 서면 워커 셋(scanner / queue / reconnector)이 돈다.

목표 구조 (아직 `workers/`는 없다 — 골격만 잡는 단계):

```
app/compose.py ──builds──▶ core.Core
core.Core ──instantiates──▶ workers/scanner.Scanner
                           workers/queue.Queue
                           workers/reconnector.Reconnector
workers/* ──use──▶ link.Link
```

계약:
- **워커는 core가 인스턴스화한다.** 워커 모듈은 `core`를 import하지 않는다(의존 방향: core → workers → link).
- `app/compose.py`가 유일한 조립 지점이다 — 설정(`Settings`)을 읽어 core와 워커 옵션을 한 곳에서 묶는다. 다른 곳에서 `Core(...)`를 직접 만들지 않는다.
- **실패 대기는 bounded여야 한다** — `Link.wait_for_link()`는 정해진 시간 안에 `LinkTimeout`으로 끝나야 한다. **현재 미구현**: `timeout` 인자는 받지만 무시되고 링크가 설 때까지 무한 대기한다. `tests/test_characterization.py`가 이 현재 동작을 고정하고 있다.

실제 링크는 BLE 기기라 sandbox에서 세울 수 없다. `Link`는 `transport` 콜러블(연결됐으면 True)을 주입받고, 테스트는 가짜 transport를 넣는다.

테스트: `python3 -m unittest discover -s tests -t .` (`workers/`가 없어 `tests/test_core.py`는 현재 skip된다)
MD

cat > link.py <<'PY'
"""기기 링크. transport()가 True를 돌려주면 링크가 선 것으로 본다."""
import time


class LinkTimeout(Exception):
    """예약됨 — 아직 아무 데서도 raise하지 않는다."""


class Link:
    POLL_INTERVAL = 0.01

    def __init__(self, transport=None, sleep=time.sleep):
        self._transport = transport or (lambda: False)
        self._sleep = sleep
        self._deadline = None
        self.connected = False
        self.polls = 0

    def wait_for_link(self, timeout=None):
        """링크가 설 때까지 기다린다. timeout은 아직 반영되지 않는다 — 실패 시 무한 대기."""
        self._deadline = None
        while not self._transport():
            self.polls += 1
            self._sleep(self.POLL_INTERVAL)
        self.connected = True
        return self
PY

cat > core.py <<'PY'
"""core: 워커를 인스턴스화하고 수명을 관리한다. 워커는 core를 import하지 않는다."""
from link import Link
from workers.queue import Queue
from workers.reconnector import Reconnector
from workers.scanner import Scanner


class Core:
    def __init__(self, link, scanner, queue, reconnector):
        self.link = link
        self.scanner = scanner
        self.queue = queue
        self.reconnector = reconnector
        self.running = False

    def start(self):
        self.link.wait_for_link()
        self.scanner.start()
        self.reconnector.start()
        self.running = True

    def stop(self):
        self.reconnector.stop()
        self.scanner.stop()
        self.running = False


def build_core(link=None, scan_interval=1.0, queue_depth=16, reconnect_backoff=0.5):
    link = link or Link()
    return Core(
        link,
        Scanner(link, interval=scan_interval),
        Queue(depth=queue_depth),
        Reconnector(link, backoff=reconnect_backoff),
    )
PY

cat > app/compose.py <<'PY'
"""조립 지점. 설정을 읽어 core와 워커 옵션을 한 곳에서 묶는다."""
import os
from typing import Optional
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    scan_interval: float = 1.0
    queue_depth: int = 16
    reconnect_backoff: float = 0.5
    link_timeout: Optional[float] = None  # None = 무한 대기 (현재 동작)


def settings_from_env(env=None) -> Settings:
    env = os.environ if env is None else env
    raw_timeout = env.get("LINKD_LINK_TIMEOUT")
    return Settings(
        scan_interval=float(env.get("LINKD_SCAN_INTERVAL", 1.0)),
        queue_depth=int(env.get("LINKD_QUEUE_DEPTH", 16)),
        reconnect_backoff=float(env.get("LINKD_RECONNECT_BACKOFF", 0.5)),
        link_timeout=None if raw_timeout in (None, "") else float(raw_timeout),
    )


def compose(settings: Settings, link=None):
    from core import build_core  # workers/ 가 아직 없어 import를 늦춘다

    core = build_core(
        link=link,
        scan_interval=settings.scan_interval,
        queue_depth=settings.queue_depth,
        reconnect_backoff=settings.reconnect_backoff,
    )
    # link_timeout은 아직 core/link로 전달되지 않는다.
    return core
PY

cat > tests/test_link.py <<'PY'
import unittest

from link import Link


class LinkTest(unittest.TestCase):
    def test_returns_once_transport_is_up(self):
        calls = iter([False, False, True])
        link = Link(transport=lambda: next(calls), sleep=lambda _: None)
        link.wait_for_link()
        self.assertTrue(link.connected)
        self.assertEqual(link.polls, 2)
PY

cat > tests/test_characterization.py <<'PY'
"""현재 동작 고정: wait_for_link는 실패 시 무한 대기한다(deadline 없음). 무한 대기 자체는 재현할 수 없으므로
timeout=None 수용과 _deadline is None 상태로 단언한다."""
import unittest

from link import Link


class WaitForeverCharacterization(unittest.TestCase):
    def test_timeout_none_is_accepted_and_no_deadline_is_set(self):
        link = Link(transport=lambda: True, sleep=lambda _: None)
        link.wait_for_link(timeout=None)
        self.assertIsNone(link._deadline)
        self.assertTrue(link.connected)

    def test_timeout_argument_is_currently_ignored(self):
        link = Link(transport=lambda: True, sleep=lambda _: None)
        link.wait_for_link(timeout=5)
        self.assertIsNone(link._deadline)
PY

cat > tests/test_compose.py <<'PY'
import unittest

from app.compose import Settings, settings_from_env


class SettingsTest(unittest.TestCase):
    def test_defaults(self):
        self.assertEqual(settings_from_env({}), Settings())

    def test_link_timeout_from_env(self):
        self.assertEqual(settings_from_env({"LINKD_LINK_TIMEOUT": "2.5"}).link_timeout, 2.5)
PY

cat > tests/test_core.py <<'PY'
import unittest

try:
    import core
except ImportError:  # workers/ 가 아직 없다
    core = None


@unittest.skipIf(core is None, "workers/ not present yet; core cannot be imported")
class CoreTest(unittest.TestCase):
    def test_build_core_wires_workers(self):
        from link import Link

        c = core.build_core(link=Link(transport=lambda: True, sleep=lambda _: None))
        c.start()
        self.assertTrue(c.running)
        c.stop()
        self.assertFalse(c.running)
PY

cat > .gitignore <<'TXT'
__pycache__/
TXT

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "linkd: skeleton with link, core (workers pending), compose"
