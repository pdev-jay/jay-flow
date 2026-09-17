#!/usr/bin/env bash
# jay-flow eval fixture: 승인된 plan 1개 + red 테스트가 있는 최소 Python 저장소.
# 실행 시점의 cwd = 이 run의 빈 workspace.
set -euo pipefail

mkdir -p ledger tests .plans/ledger-report
: > ledger/__init__.py
: > tests/__init__.py

cat > tests/test_models.py <<'PY'
import unittest

from ledger.models import Entry


class EntryTest(unittest.TestCase):
    def test_fields(self):
        e = Entry(date="2026-01-05", amount=1200, category="food")
        self.assertEqual((e.date, e.amount, e.category), ("2026-01-05", 1200, "food"))

    def test_equality(self):
        self.assertEqual(Entry("2026-01-05", 1, "a"), Entry("2026-01-05", 1, "a"))
PY

cat > tests/test_parse.py <<'PY'
import unittest

from ledger.models import Entry
from ledger.parse import parse_line, parse_lines


class ParseTest(unittest.TestCase):
    def test_parse_line(self):
        self.assertEqual(parse_line("2026-01-05,1200,food"), Entry("2026-01-05", 1200, "food"))

    def test_strips_whitespace(self):
        self.assertEqual(parse_line(" 2026-01-05 , 1200 , food \n"), Entry("2026-01-05", 1200, "food"))

    def test_bad_field_count(self):
        with self.assertRaises(ValueError):
            parse_line("2026-01-05,1200")

    def test_non_int_amount(self):
        with self.assertRaises(ValueError):
            parse_line("2026-01-05,abc,food")

    def test_parse_lines_skips_blank(self):
        lines = ["2026-01-05,1,a", "", "   ", "2026-01-06,2,b"]
        self.assertEqual(parse_lines(lines), [Entry("2026-01-05", 1, "a"), Entry("2026-01-06", 2, "b")])
PY

cat > tests/test_report.py <<'PY'
import unittest

from ledger.models import Entry
from ledger.report import format_report, total_by_category


ENTRIES = [
    Entry("2026-01-05", 1200, "food"),
    Entry("2026-01-06", 500, "rent"),
    Entry("2026-01-07", 500, "food"),
]


class ReportTest(unittest.TestCase):
    def test_total_by_category(self):
        self.assertEqual(total_by_category(ENTRIES), {"food": 1700, "rent": 500})

    def test_format_report_sorted_by_category(self):
        self.assertEqual(format_report(ENTRIES), "food: 1700\nrent: 500")

    def test_format_report_empty(self):
        self.assertEqual(format_report([]), "")
PY

cat > .plans/ledger-report/v1.md <<'MD'
# ledger: CSV 파싱 + 카테고리별 합계 리포트
status: in-progress
version: 1

## 원인·배경
기능류. 출발점: 한 줄짜리 CSV 가계부(`날짜,금액,카테고리`)를 읽어 카테고리별 합계를 텍스트로 보고 싶다. 현재 `ledger/` 패키지는 비어 있고 테스트만 red 상태로 존재한다.

## 목표
`tests/` 아래 10개 테스트가 전부 green. 외부 의존성 없음(표준 라이브러리만).

## 접근
세 모듈로 나눈다. `models.Entry`(공유 타입) → `parse`(문자열→Entry) / `report`(Entry 목록→집계·포맷). parse와 report는 서로를 모른다.

## 구조
구조 관례: 신규 — 모듈은 `ledger/<역할>.py` 한 파일에 하나, 함수는 snake_case, 입력 오류는 `ValueError`(메시지에 원문 라인 포함). 클래스는 `dataclass`. 불변식: `Entry.amount`는 int(타입).

```
┌ ledger ──────────────────────────────┐
│  models.py*  Entry(date, amount, category)
│      ▲                 ▲
│  parse.py*         report.py*
│  parse_line        total_by_category
│  parse_lines       format_report
└──────────────────────────────────────┘
```

## 의존성
표준 라이브러리만. `dataclasses`.

## 영향 범위
신규 파일 3개. 기존 사용처 없음.

## 잠재 에러
- 필드 수 ≠ 3 → ValueError
- 금액이 int로 안 바뀜 → ValueError
- 빈 줄·공백만 있는 줄은 `parse_lines`에서 건너뛴다(에러 아님)
- 빈 목록 리포트 → 빈 문자열

## 범위
포함: 위 세 모듈. 제외: 파일 I/O, CLI, 날짜 검증, 음수 금액 처리.

## 미해결·전제
- (해석) "카테고리 순 정렬"은 문자열 오름차순으로 해석 — 대안: 합계 내림차순.

## Tasks
- [ ] 1. `Entry` dataclass 정의 — plan §구조, 파일: `ledger/models.py`, 완료: `python3 -m unittest tests.test_models` green   (공유분)
- [ ] 2. `parse_line(line) -> Entry`, `parse_lines(lines) -> list[Entry]` — plan §접근 §잠재 에러, 파일: `ledger/parse.py`, 완료: `python3 -m unittest tests.test_parse` green
- [ ] 3. `total_by_category(entries) -> dict[str, int]`, `format_report(entries) -> str`("<category>: <total>" 줄, 카테고리 오름차순, 줄바꿈 연결) — plan §접근 §미해결·전제, 파일: `ledger/report.py`, 완료: `python3 -m unittest tests.test_report` green
MD

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "fixture: red tests + approved plan"
