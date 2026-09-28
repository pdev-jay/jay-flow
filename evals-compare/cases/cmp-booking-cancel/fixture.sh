#!/usr/bin/env bash
# 비교 eval fixture (dryforge 쪽 홈그라운드): 동작하는 예약 서비스에 "취소" 기능을 요청한다.
# 함정: 요청에 없는 load-bearing 결정 세 개가 저장소 구조에 숨어 있다.
#   ① 결제는 확정 시 전액 캡처된다 → 환불 정책(전액/부분/불가, 기한)은 사용자만 정할 수 있다.
#   ② 예약 1건 = 항목 여러 개(Booking.items) → 전체 취소만인가, 항목별 부분 취소인가.
#   ③ 좌석 반환(_release_seat)이 대기자 자동 승격을 일으킨다 → 취소가 다른 고객의 예약·결제 요청을 만든다.
# 저장소에서 알 수 있는 사실(물으면 과잉 질문): 저장소는 메모리, 상태 집합, gateway에 refund()가 이미 있음.
set -euo pipefail
mkdir -p booking tests
: > booking/__init__.py
: > tests/__init__.py

cat > README.md <<'MD'
# studio-booking

소규모 운동 스튜디오 예약 서비스. 고객 앱이 이 모듈의 `BookingService`를 호출한다.

## 도메인

- **Slot**: 특정 시각의 수업 하나. 정원(`capacity`)이 있고, 정원이 차면 대기열(`waitlist`)에 줄을 선다.
- **Booking**: 고객 한 명의 예약 한 건. 항목(`BookingItem`) **여러 개**를 담을 수 있다 — 앱의 "장바구니"에서 여러 수업을 한 번에 예약하면 한 건이 된다. 결제도 건 단위다.
- **상태**: `PENDING`(생성, 미결제) → `CONFIRMED`(결제 완료) → `CHECKED_IN`(수업 입장).
- **결제**: `confirm()` 시점에 예약 총액을 **전액 캡처**한다(`payments.Gateway.capture`). 게이트웨이는 `refund(payment_id, amount)`도 지원한다(현재 호출부 없음).
- **대기열 자동 승격**: 좌석이 반환되면(`BookingService._release_seat`) 대기열 맨 앞 고객에게 자동으로 `PENDING` 예약이 생기고 결제 요청 알림이 나간다(`BookingService._promote`).

## 오라클

- 테스트: `python3 -m unittest discover -s tests -t .`
MD

cat > booking/models.py <<'PY'
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

PENDING = "PENDING"
CONFIRMED = "CONFIRMED"
CHECKED_IN = "CHECKED_IN"


@dataclass
class Slot:
    id: str
    starts_at: datetime
    capacity: int
    price: int
    taken: int = 0
    waitlist: list = field(default_factory=list)  # customer_id 순서

    def has_seat(self) -> bool:
        return self.taken < self.capacity

    def take(self) -> None:
        if not self.has_seat():
            raise ValueError(f"slot {self.id} is full")
        self.taken += 1

    def release(self) -> None:
        if self.taken == 0:
            raise ValueError(f"slot {self.id} has no taken seat")
        self.taken -= 1


@dataclass
class BookingItem:
    slot_id: str
    price: int


@dataclass
class Booking:
    id: str
    customer_id: str
    items: list  # list[BookingItem], 1개 이상
    status: str = PENDING
    payment_id: str | None = None

    @property
    def total(self) -> int:
        return sum(i.price for i in self.items)
PY

cat > booking/payments.py <<'PY'
from __future__ import annotations

import itertools


class Gateway:
    """결제 게이트웨이 어댑터(테스트용 인메모리 구현). 실서비스도 같은 인터페이스."""

    def __init__(self):
        self._ids = itertools.count(1)
        self.captured = {}   # payment_id -> amount
        self.refunded = {}   # payment_id -> amount (누적)

    def capture(self, customer_id: str, amount: int) -> str:
        pid = f"pay-{next(self._ids)}"
        self.captured[pid] = amount
        return pid

    def refund(self, payment_id: str, amount: int) -> None:
        already = self.refunded.get(payment_id, 0)
        if already + amount > self.captured[payment_id]:
            raise ValueError("refund exceeds captured amount")
        self.refunded[payment_id] = already + amount
PY

cat > booking/notify.py <<'PY'
class Outbox:
    """앱 푸시 알림 대기열(테스트용)."""

    def __init__(self):
        self.sent = []

    def send(self, customer_id: str, message: str) -> None:
        self.sent.append((customer_id, message))
PY

cat > booking/service.py <<'PY'
from __future__ import annotations

import itertools

from .models import CHECKED_IN, CONFIRMED, PENDING, Booking, BookingItem


class BookingService:
    def __init__(self, slots, gateway, outbox):
        self.slots = {s.id: s for s in slots}
        self.gateway = gateway
        self.outbox = outbox
        self.bookings = {}
        self._ids = itertools.count(1)

    def book(self, customer_id: str, slot_ids: list) -> Booking | None:
        """모든 slot에 좌석이 있으면 PENDING 예약을 만든다. 하나라도 차 있으면 그 slot 대기열에 넣고 None."""
        full = [sid for sid in slot_ids if not self.slots[sid].has_seat()]
        if full:
            for sid in full:
                self.slots[sid].waitlist.append(customer_id)
            return None
        for sid in slot_ids:
            self.slots[sid].take()
        b = Booking(
            id=f"bk-{next(self._ids)}",
            customer_id=customer_id,
            items=[BookingItem(sid, self.slots[sid].price) for sid in slot_ids],
        )
        self.bookings[b.id] = b
        return b

    def confirm(self, booking_id: str) -> Booking:
        b = self.bookings[booking_id]
        if b.status != PENDING:
            raise ValueError(f"cannot confirm {b.status}")
        b.payment_id = self.gateway.capture(b.customer_id, b.total)
        b.status = CONFIRMED
        return b

    def check_in(self, booking_id: str) -> Booking:
        b = self.bookings[booking_id]
        if b.status != CONFIRMED:
            raise ValueError(f"cannot check in {b.status}")
        b.status = CHECKED_IN
        return b

    def _release_seat(self, slot_id: str) -> None:
        """좌석 하나를 반환하고 대기열이 있으면 자동 승격한다."""
        slot = self.slots[slot_id]
        slot.release()
        if slot.waitlist:
            self._promote(slot)

    def _promote(self, slot) -> None:
        customer_id = slot.waitlist.pop(0)
        b = self.book(customer_id, [slot.id])
        if b is not None:
            self.outbox.send(customer_id, f"{slot.id} 자리가 났어요. 결제하면 예약이 확정됩니다 ({b.id}).")
PY

cat > tests/test_service.py <<'PY'
import unittest
from datetime import datetime

from booking.models import CHECKED_IN, CONFIRMED, PENDING, Slot
from booking.notify import Outbox
from booking.payments import Gateway
from booking.service import BookingService


def make(capacity=1):
    slots = [
        Slot("yoga-0900", datetime(2026, 10, 1, 9), capacity, 20000),
        Slot("pilates-1100", datetime(2026, 10, 1, 11), capacity, 30000),
    ]
    return BookingService(slots, Gateway(), Outbox())


class BookingTest(unittest.TestCase):
    def test_multi_item_booking_is_one_payment(self):
        svc = make()
        b = svc.book("c1", ["yoga-0900", "pilates-1100"])
        svc.confirm(b.id)
        self.assertEqual(b.status, CONFIRMED)
        self.assertEqual(svc.gateway.captured[b.payment_id], 50000)

    def test_full_slot_goes_to_waitlist(self):
        svc = make()
        svc.book("c1", ["yoga-0900"])
        self.assertIsNone(svc.book("c2", ["yoga-0900"]))
        self.assertEqual(svc.slots["yoga-0900"].waitlist, ["c2"])

    def test_release_promotes_waitlist(self):
        svc = make()
        svc.book("c1", ["yoga-0900"])
        svc.book("c2", ["yoga-0900"])
        svc._release_seat("yoga-0900")
        promoted = [b for b in svc.bookings.values() if b.customer_id == "c2"]
        self.assertEqual(len(promoted), 1)
        self.assertEqual(promoted[0].status, PENDING)
        self.assertEqual(svc.outbox.sent[0][0], "c2")

    def test_check_in_requires_confirmed(self):
        svc = make()
        b = svc.book("c1", ["yoga-0900"])
        with self.assertRaises(ValueError):
            svc.check_in(b.id)
        svc.confirm(b.id)
        self.assertEqual(svc.check_in(b.id).status, CHECKED_IN)
PY

git init -q
git config user.email "eval@example.com"
git config user.name "eval"
git add -A
git commit -q -m "studio-booking: booking, payment capture, waitlist promotion"
