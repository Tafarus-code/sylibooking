"""Availability logic: when is a space free, and what can still be booked.

A Reservation stores only a start time, so every booking is treated as running
for ``settings.RESERVATION_DURATION_MINUTES``. Two bookings on the same space
clash when those windows overlap.

A cancelled reservation frees its slot. Everything else — pending, confirmed,
completed — holds it, so a merchant cannot accidentally double-book over a
visit that already happened.

A deactivated space is offered no slots at all. Its existing bookings still
hold their windows, because those sittings are still happening.
"""

from datetime import datetime, time, timedelta

from django.conf import settings
from django.utils import timezone

from establishments.models import Space

from .models import Reservation

#: Statuses that keep a slot occupied.
BLOCKING_STATUSES = [
    Reservation.Status.PENDING,
    Reservation.Status.CONFIRMED,
    Reservation.Status.COMPLETED,
]


def reservation_duration():
    """How long one booking occupies its space."""
    return timedelta(minutes=settings.RESERVATION_DURATION_MINUTES)


def _parse_window(value):
    hour, minute = (int(part) for part in value.split(':'))
    return time(hour=hour, minute=minute)


def slot_starts(day):
    """Candidate start times on ``day``, as timezone-aware datetimes.

    Walks from AVAILABILITY_WINDOW_START to AVAILABILITY_WINDOW_END in
    AVAILABILITY_SLOT_MINUTES steps. The end of the window is the last time a
    booking may *start*, not the closing time.
    """
    step = timedelta(minutes=settings.AVAILABILITY_SLOT_MINUTES)
    current = timezone.make_aware(
        datetime.combine(day, _parse_window(settings.AVAILABILITY_WINDOW_START))
    )
    last = timezone.make_aware(
        datetime.combine(day, _parse_window(settings.AVAILABILITY_WINDOW_END))
    )

    slots = []
    while current <= last:
        slots.append(current)
        current += step
    return slots


def clashing_reservations(space, start, exclude_pk=None):
    """Reservations on ``space`` whose window overlaps a booking at ``start``.

    Two windows [a, a+d) and [b, b+d) overlap when a < b+d and b < a+d, which
    with a fixed duration reduces to the single range below.
    """
    duration = reservation_duration()
    queryset = Reservation.objects.filter(
        space=space,
        status__in=BLOCKING_STATUSES,
        datetime__gt=start - duration,
        datetime__lt=start + duration,
    )
    if exclude_pk is not None:
        queryset = queryset.exclude(pk=exclude_pk)
    return queryset


def is_space_available(space, start, exclude_pk=None):
    """True when ``space`` has nothing booked across the window at ``start``."""
    return not clashing_reservations(space, start, exclude_pk=exclude_pk).exists()


def availability_for_establishment(establishment, day, party_size=None):
    """Per-space slot grid for ``day``.

    Spaces too small for ``party_size`` are dropped entirely rather than
    returned with every slot marked unavailable — a customer asking for six
    seats has no use for a two-top.

    Returns a list of ``{'space': Space, 'slots': [{'start', 'available'}]}``.
    """
    # Only spaces still in service. A deactivated table keeps its bookings and
    # its history, but must never be offered again.
    spaces = Space.objects.filter(establishment=establishment, is_active=True)
    if party_size is not None:
        spaces = spaces.filter(capacity__gte=party_size)
    spaces = list(spaces)
    if not spaces:
        return []

    slots = slot_starts(day)
    if not slots:
        return [{'space': space, 'slots': []} for space in spaces]

    # One query for the whole day instead of one per space per slot.
    duration = reservation_duration()
    booked = Reservation.objects.filter(
        space__in=spaces,
        status__in=BLOCKING_STATUSES,
        datetime__gt=slots[0] - duration,
        datetime__lt=slots[-1] + duration,
    ).values_list('space_id', 'datetime')

    taken = {}
    for space_id, start in booked:
        taken.setdefault(space_id, []).append(start)

    results = []
    for space in spaces:
        starts = taken.get(space.id, [])
        results.append(
            {
                'space': space,
                'slots': [
                    {
                        'start': slot,
                        'available': all(
                            not (slot - duration < booked_at < slot + duration)
                            for booked_at in starts
                        ),
                    }
                    for slot in slots
                ],
            }
        )
    return results