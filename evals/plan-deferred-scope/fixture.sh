#!/usr/bin/env bash
# jay-flow eval fixture (plan): 항목 CLI. create는 저장+업로드, edit는 저장만 하고 "saved"를 찍는다(업로드 없음·에러 없음 — silent fail).
set -euo pipefail
mkdir -p tests tools data
: > tests/__init__.py

cat > README.md <<'MD'
# itemcli

항목(item)을 로컬에 저장하고 사내 서버에 업로드하는 CLI. 서브커맨드는 `create`, `edit`.

계약:
- `create`/`edit` 모두 **서버 업로드가 완료돼야** 성공(`saved <id>`)으로 보고한다. 로컬 저장만 된 상태는 성공이 아니다.
- 업로드 실패는 사용자에게 보여야 한다: stderr에 `upload failed: <이유>`, exit code 1. 로컬 저장은 되돌리지 않는다(재시도 가능).
- 항목 id는 1부터 증가하는 정수. 이름은 비어 있을 수 없다.

사내 서버는 sandbox에서 접근할 수 없으므로 `server.py`는 스텁이다 — 업로드 호출을 `data/uploads.log`에 한 줄씩 기록한다. `ITEMCLI_FAIL_UPLOAD=1`이면 업로드가 실패한다(실패 경로 테스트용).

실행:
- `python3 cli.py create <name>` / `python3 cli.py edit <id> --name <name>`
- `python3 tools/show_uploads.py` — 업로드 기록을 보여준다
- 데이터 위치는 `ITEMCLI_HOME`(기본 `./data`)

테스트: `python3 -m unittest discover -s tests -t .`
MD

cat > store.py <<'PY'
"""로컬 JSON 저장소. 파일: $ITEMCLI_HOME/items.json"""
import json
import os


def _home() -> str:
    return os.environ.get("ITEMCLI_HOME", "data")


def _path() -> str:
    return os.path.join(_home(), "items.json")


def load() -> dict:
    try:
        with open(_path(), encoding="utf-8") as f:
            return {int(k): v for k, v in json.load(f).items()}
    except FileNotFoundError:
        return {}


def save(items: dict) -> None:
    os.makedirs(_home(), exist_ok=True)
    with open(_path(), "w", encoding="utf-8") as f:
        json.dump({str(k): v for k, v in items.items()}, f, ensure_ascii=False, indent=2)


def add(name: str) -> dict:
    if not name:
        raise ValueError("name must not be empty")
    items = load()
    item_id = max(items, default=0) + 1
    item = {"id": item_id, "name": name}
    items[item_id] = item
    save(items)
    return item


def update(item_id: int, name: str) -> dict:
    if not name:
        raise ValueError("name must not be empty")
    items = load()
    if item_id not in items:
        raise KeyError(f"no such item: {item_id}")
    item = {"id": item_id, "name": name}
    items[item_id] = item
    save(items)
    return item
PY

cat > server.py <<'PY'
"""사내 업로드 서버 스텁. 실제 서버는 sandbox에서 닿지 않으므로 호출을 $ITEMCLI_HOME/uploads.log에 기록한다."""
import json
import os


class UploadError(Exception):
    pass


def _log_path() -> str:
    return os.path.join(os.environ.get("ITEMCLI_HOME", "data"), "uploads.log")


def upload(item: dict) -> None:
    if os.environ.get("ITEMCLI_FAIL_UPLOAD") == "1":
        raise UploadError("server rejected item %s" % item.get("id"))
    os.makedirs(os.path.dirname(_log_path()), exist_ok=True)
    with open(_log_path(), "a", encoding="utf-8") as f:
        f.write(json.dumps(item, ensure_ascii=False) + "\n")


def uploads() -> list:
    try:
        with open(_log_path(), encoding="utf-8") as f:
            return [json.loads(line) for line in f if line.strip()]
    except FileNotFoundError:
        return []
PY

cat > cli.py <<'PY'
import argparse
import sys

import server
import store


def cmd_create(args) -> int:
    item = store.add(args.name)
    try:
        server.upload(item)
    except server.UploadError as e:
        print(f"upload failed: {e}", file=sys.stderr)
        return 1
    print(f"saved {item['id']}")
    return 0


def cmd_edit(args) -> int:
    try:
        item = store.update(args.id, args.name)
    except KeyError as e:
        print(f"error: {e.args[0]}", file=sys.stderr)
        return 1
    # TODO 서버 배선
    print(f"saved {item['id']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="itemcli")
    sub = p.add_subparsers(dest="command", required=True)
    c = sub.add_parser("create", help="create an item")
    c.add_argument("name")
    c.set_defaults(func=cmd_create)
    e = sub.add_parser("edit", help="edit an item")
    e.add_argument("id", type=int)
    e.add_argument("--name", required=True)
    e.set_defaults(func=cmd_edit)
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
PY

cat > tools/show_uploads.py <<'PY'
"""업로드 기록($ITEMCLI_HOME/uploads.log)을 출력한다."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import server  # noqa: E402

if __name__ == "__main__":
    rows = server.uploads()
    if not rows:
        print("(no uploads)")
    for r in rows:
        print(f"uploaded id={r['id']} name={r['name']}")
PY

cat > data/items.json <<'JSON'
{
  "1": {
    "id": 1,
    "name": "seed"
  }
}
JSON

cat > tests/helpers.py <<'PY'
import os
import tempfile
import unittest


class TempHomeTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._old = os.environ.get("ITEMCLI_HOME")
        os.environ["ITEMCLI_HOME"] = self._tmp.name
        os.environ.pop("ITEMCLI_FAIL_UPLOAD", None)

    def tearDown(self):
        if self._old is None:
            os.environ.pop("ITEMCLI_HOME", None)
        else:
            os.environ["ITEMCLI_HOME"] = self._old
        os.environ.pop("ITEMCLI_FAIL_UPLOAD", None)
        self._tmp.cleanup()
PY

cat > tests/test_create.py <<'PY'
import contextlib
import io
import os

import cli
import server
import store
from tests.helpers import TempHomeTest


class CreateTest(TempHomeTest):
    def test_create_saves_and_uploads(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cli.main(["create", "apple"])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue(), "saved 1\n")
        self.assertEqual(store.load()[1]["name"], "apple")
        self.assertEqual([u["id"] for u in server.uploads()], [1])

    def test_create_upload_failure_is_visible(self):
        os.environ["ITEMCLI_FAIL_UPLOAD"] = "1"
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = cli.main(["create", "apple"])
        self.assertEqual(rc, 1)
        self.assertEqual(out.getvalue(), "")
        self.assertIn("upload failed", err.getvalue())
        self.assertEqual(store.load()[1]["name"], "apple")
        self.assertEqual(server.uploads(), [])
PY

cat > tests/test_edit.py <<'PY'
import contextlib
import io

import cli
import store
from tests.helpers import TempHomeTest


class EditTest(TempHomeTest):
    def test_edit_updates_store(self):
        store.add("apple")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cli.main(["edit", "1", "--name", "pear"])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue(), "saved 1\n")
        self.assertEqual(store.load()[1]["name"], "pear")

    def test_edit_missing_id_fails(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = cli.main(["edit", "9", "--name", "pear"])
        self.assertEqual(rc, 1)
        self.assertIn("no such item", err.getvalue())
PY

cat > .gitignore <<'TXT'
__pycache__/
data/uploads.log
TXT

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "itemcli: create/edit CLI with upload stub"
