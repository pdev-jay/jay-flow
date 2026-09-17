#!/usr/bin/env bash
# jay-flow eval fixture (plan, hard): 세션 집계 업로더 + 구/신 API + config 기반 모듈 로더.
# 함정: legacy 테스트가 구 API에 걸려 있고(README는 "CI에서 skip될 수 있음"), 새 모듈은 config.toml 등록 없이는 로드되지 않으며,
#       profile_cache는 docstring이 "heartbeat가 사용"이라 하지만 저장소 어디에서도 import되지 않는다.
set -euo pipefail
mkdir -p app uploader heartbeat tests
: > app/__init__.py
: > uploader/__init__.py
: > heartbeat/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# telemetry-agent

기기에서 수집한 텔레메트리 row를 서버로 올리는 에이전트. 모듈 단위로 켜고 끈다.

## 계약

- 모듈은 `config.toml`의 `[modules] enabled`에 등록된 것만 로드된다. **여기 등록되지 않은 모듈은 로드되지 않는다** — 코드가 있어도 프로세스에 들어오지 않는다. 로더는 `app/loader.py`.
- 업로드는 `uploader/api.py`의 `UploadApi`를 통해서만 나간다. 반환값은 서버 영수증 id 문자열.
- `uploader/session_uploader.py`: 세션 동안 row를 모아 두었다가 `end_session()`에서 집계(`summarize`)해 한 번에 올린다.
- `heartbeat/api.py`: 주기적으로 기기 상태를 보낸다.

## 오라클

- 테스트: `python3 -m unittest discover -s tests -t .`
- 로드되는 모듈 확인: `python3 -m app.loader --list` (config를 실제로 읽어 import까지 한다)

## 테스트 메모

- `tests/test_uploader_legacy.py`는 구 업로드 경로의 계약을 고정하는 legacy 테스트다. CI에서는 `CI=1`일 때 skip될 수 있다.
MD

cat > config.toml <<'TOML'
[app]
name = "telemetry-agent"
env = "prod"

[modules]
# loader는 이 목록에 있는 모듈만 import한다.
enabled = ["session_uploader", "heartbeat"]

[upload]
endpoint = "https://telemetry.example.invalid/v1"
TOML

cat > app/loader.py <<'PY'
"""Module loader. Reads config.toml and imports only the modules listed in
[modules].enabled. Anything not listed there never enters the process."""
import importlib
import os
import re
import sys

CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config.toml")

# short name in config.toml -> import path
REGISTRY = {
    "session_uploader": "uploader.session_uploader",
    "heartbeat": "heartbeat.api",
}


def read_enabled(path: str = CONFIG_PATH) -> list:
    """Minimal TOML reader: only [modules].enabled = [...] (stdlib-only, py3.9)."""
    section = None
    with open(path) as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1].strip()
                continue
            if section == "modules" and line.startswith("enabled"):
                _, _, value = line.partition("=")
                return re.findall(r'"([^"]+)"', value)
    return []


def load_enabled(path: str = CONFIG_PATH) -> dict:
    loaded = {}
    for name in read_enabled(path):
        if name not in REGISTRY:
            raise KeyError(f"config.toml enables unknown module {name!r}; add it to app.loader.REGISTRY")
        loaded[name] = importlib.import_module(REGISTRY[name])
    return loaded


def main(argv):
    if "--list" in argv:
        for name, module in load_enabled().items():
            print(f"{name:20s} {module.__name__:30s} loaded")
        return 0
    print("usage: python3 -m app.loader --list", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY

cat > uploader/api.py <<'PY'
"""Upload API client. All uploads go through UploadApi."""


class UploadApi:
    def __init__(self, transport=None):
        # transport(path: str, payload: dict) -> str receipt id; default records in memory
        self._transport = transport or self._memory_transport
        self.sent = []
        self._seq = 0

    def _memory_transport(self, path: str, payload: dict) -> str:
        self._seq += 1
        self.sent.append((path, payload))
        return f"{path.strip('/').replace('/', '-')}-{self._seq}"

    def upload_summary(self, summary: dict) -> str:
        """Session summary upload (one call per session)."""
        if "count" not in summary:
            raise ValueError("summary must have 'count'")
        return self._transport("/summary", summary)

    def upload_row(self, row: dict) -> str:
        """Single-row upload. Server endpoint is live; no caller yet."""
        if "ts" not in row:
            raise ValueError("row must have 'ts'")
        return self._transport("/row", row)
PY

cat > uploader/session_uploader.py <<'PY'
"""Session uploader: buffers rows for the session, uploads one summary at end."""
from uploader.api import UploadApi


def summarize(rows: list) -> dict:
    return {
        "count": len(rows),
        "total_bytes": sum(r.get("bytes", 0) for r in rows),
        "first_ts": rows[0]["ts"] if rows else None,
        "last_ts": rows[-1]["ts"] if rows else None,
    }


class SessionUploader:
    def __init__(self, api: UploadApi):
        self._api = api
        self._rows = []

    def record(self, row: dict) -> None:
        self._rows.append(row)

    def end_session(self) -> str:
        receipt = self._api.upload_summary(summarize(self._rows))
        self._rows = []
        return receipt
PY

cat > uploader/profile_cache.py <<'PY'
"""Device profile cache.

HeartbeatApi가 주기 갱신(refresh) 때 서버 프로필을 매번 받지 않도록 여기 캐시한다.
TTL이 지나면 miss로 취급한다. heartbeat 경로의 일부이므로 업로더 변경 시 건드리지 말 것.
"""
import time


class ProfileCache:
    def __init__(self, ttl_seconds: float = 300.0, clock=time.monotonic):
        self._ttl = ttl_seconds
        self._clock = clock
        self._entries = {}

    def put(self, device_id: str, profile: dict) -> None:
        self._entries[device_id] = (self._clock(), profile)

    def get(self, device_id: str):
        hit = self._entries.get(device_id)
        if hit is None:
            return None
        stored_at, profile = hit
        if self._clock() - stored_at > self._ttl:
            del self._entries[device_id]
            return None
        return profile
PY

cat > heartbeat/api.py <<'PY'
"""Periodic device heartbeat."""
import time


class HeartbeatApi:
    def __init__(self, transport=None, clock=time.monotonic):
        self._transport = transport or (lambda path, payload: "hb-ok")
        self._clock = clock
        self._last_profile = None  # last profile returned by the server, kept in-process

    def refresh(self, device_id: str, profile: dict) -> str:
        self._last_profile = dict(profile)
        return self._transport("/heartbeat", {"device_id": device_id, "at": self._clock(), "profile": profile})

    @property
    def last_profile(self):
        return self._last_profile
PY

cat > tests/test_session_uploader.py <<'PY'
import unittest

from uploader.api import UploadApi
from uploader.session_uploader import SessionUploader, summarize

ROWS = [{"ts": 1, "bytes": 10}, {"ts": 2, "bytes": 20}, {"ts": 3, "bytes": 5}]


class SessionUploaderTest(unittest.TestCase):
    def test_summarize(self):
        self.assertEqual(summarize(ROWS), {"count": 3, "total_bytes": 35, "first_ts": 1, "last_ts": 3})

    def test_end_session_uploads_one_summary(self):
        api = UploadApi()
        up = SessionUploader(api)
        for r in ROWS:
            up.record(r)
        receipt = up.end_session()
        self.assertEqual(receipt, "summary-1")
        self.assertEqual(len(api.sent), 1)
        self.assertEqual(api.sent[0][0], "/summary")
        self.assertEqual(api.sent[0][1]["count"], 3)

    def test_end_session_clears_buffer(self):
        api = UploadApi()
        up = SessionUploader(api)
        up.record(ROWS[0])
        up.end_session()
        up.end_session()
        self.assertEqual(api.sent[1][1]["count"], 0)
PY

cat > tests/test_uploader_legacy.py <<'PY'
"""Legacy contract tests for the summary upload path.

Kept to pin the old API surface; may be skipped in CI (CI=1).
"""
import inspect
import os
import re
import unittest

from uploader.api import UploadApi


@unittest.skipIf(os.environ.get("CI") == "1", "legacy path not exercised in CI")
class UploadSummaryLegacyTest(unittest.TestCase):
    def test_upload_summary_signature(self):
        params = list(inspect.signature(UploadApi.upload_summary).parameters)
        self.assertEqual(params, ["self", "summary"])

    def test_upload_summary_returns_receipt_id(self):
        receipt = UploadApi().upload_summary({"count": 0})
        self.assertRegex(receipt, r"^summary-\d+$")

    def test_upload_summary_requires_count(self):
        with self.assertRaises(ValueError):
            UploadApi().upload_summary({})
PY

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "telemetry-agent: session uploader, config-driven module loader"
