#!/usr/bin/env bash
# jay-flow eval fixture (plan): 동작하는 ledger 패키지 + 계약 문서 + 실제 버그(카테고리 대소문자 미정규화).
set -euo pipefail
mkdir -p ledger tests
: > ledger/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# ledger

CSV 한 줄(`날짜,금액,카테고리`)을 읽어 카테고리별 합계를 출력한다.

계약:
- `Entry.category`는 정규화된 소문자 문자열이다. 카테고리는 대소문자를 구분하지 않는다(`Food` == `food`).
- 금액은 정수. 파싱 실패는 `ValueError`(메시지에 원문 라인 포함).

실행: `python3 -m ledger < entries.csv`
테스트: `python3 -m unittest discover -s tests -t .`
MD

cat > ledger/models.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Entry:
    date: str
    amount: int
    category: str
PY

cat > ledger/parse.py <<'PY'
from ledger.models import Entry


def parse_line(line: str) -> Entry:
    parts = [p.strip() for p in line.strip().split(",")]
    if len(parts) != 3:
        raise ValueError(f"expected 3 fields: {line!r}")
    date, amount, category = parts
    try:
        value = int(amount)
    except ValueError:
        raise ValueError(f"amount is not an int: {line!r}") from None
    return Entry(date, value, category)


def parse_lines(lines) -> list:
    return [parse_line(l) for l in lines if l.strip()]
PY

cat > ledger/report.py <<'PY'
def total_by_category(entries) -> dict:
    totals: dict = {}
    for e in entries:
        totals[e.category] = totals.get(e.category, 0) + e.amount
    return totals


def format_report(entries) -> str:
    totals = total_by_category(entries)
    return "\n".join(f"{c}: {totals[c]}" for c in sorted(totals))
PY

cat > ledger/__main__.py <<'PY'
import sys

from ledger.parse import parse_lines
from ledger.report import format_report

if __name__ == "__main__":
    print(format_report(parse_lines(sys.stdin.read().splitlines())))
PY

cat > tests/test_parse.py <<'PY'
import unittest

from ledger.models import Entry
from ledger.parse import parse_line, parse_lines


class ParseTest(unittest.TestCase):
    def test_parse_line(self):
        self.assertEqual(parse_line("2026-01-05,1200,food"), Entry("2026-01-05", 1200, "food"))

    def test_bad_field_count(self):
        with self.assertRaises(ValueError):
            parse_line("2026-01-05,1200")

    def test_parse_lines_skips_blank(self):
        self.assertEqual(parse_lines(["2026-01-05,1,a", "", "2026-01-06,2,b"]),
                         [Entry("2026-01-05", 1, "a"), Entry("2026-01-06", 2, "b")])
PY

cat > tests/test_report.py <<'PY'
import unittest

from ledger.models import Entry
from ledger.report import format_report, total_by_category

ENTRIES = [Entry("2026-01-05", 1200, "food"), Entry("2026-01-06", 500, "rent"), Entry("2026-01-07", 500, "food")]


class ReportTest(unittest.TestCase):
    def test_total_by_category(self):
        self.assertEqual(total_by_category(ENTRIES), {"food": 1700, "rent": 500})

    def test_format_report_sorted(self):
        self.assertEqual(format_report(ENTRIES), "food: 1700\nrent: 500")
PY

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "ledger: working package with contract doc"
