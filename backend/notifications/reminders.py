"""When a booking reminder is due, and what it says.

Separate from the tasks so the rules can be read and tested without a queue
in the way. A task should be a thin thing that decides when to call this.

Two rules decide timing.

A reminder goes out a fixed lead time before the booking — long enough to be
useful, short enough that the customer has not forgotten receiving it.

And it never goes out in the middle of the night. A 21:00 lounge booking with
a three-hour lead is fine; a 09:00 restaurant booking would otherwise ring a
phone at 06:00, and a reminder that wakes someone is worse than none. Inside
the quiet hours the reminder waits for morning, even if that means less
notice — a late reminder is still a reminder, a 04:00 one is a nuisance.
"""

from datetime import time, timedelta

from django.conf import settings
from django.utils import timezone

from reservations.models import Reservation


def lead_time():
    return timedelta(hours=settings.REMINDER_LEAD_HOURS)


def _quiet_hours():
    start = time.fromisoformat(settings.REMINDER_QUIET_START)
    end = time.fromisoformat(settings.REMINDER_QUIET_END)
    return start, end


def is_quiet(moment):
    """True inside the hours nobody wants their phone to make a noise.

    The window wraps midnight, so this is two comparisons rather than one.
    """
    start, end = _quiet_hours()
    local = timezone.localtime(moment).time()
    if start <= end:
        return start <= local < end
    return local >= start or local < end


def send_after(reservation):
    """The earliest moment this booking's reminder may be sent.

    The lead time, pushed out of the quiet hours if it lands in them.
    """
    due = reservation.datetime - lead_time()
    if not is_quiet(due):
        return due

    # Wait for the quiet window to end, on whichever day that is.
    _, end = _quiet_hours()
    local_due = timezone.localtime(due)
    wake = local_due.replace(
        hour=end.hour, minute=end.minute, second=0, microsecond=0
    )
    if wake < local_due:
        wake += timedelta(days=1)
    return wake


def due_reservations(now=None):
    """Bookings whose reminder should go out by now, and has not.

    Excludes anything already reminded — the log is the record — and anything
    that is no longer going to happen. Reminding somebody about a table they
    cancelled is worse than saying nothing.
    """
    from .models import Notification

    now = now or timezone.now()

    candidates = (
        Reservation.objects.filter(
            status__in=Reservation.OPEN_STATUSES,
            datetime__gt=now,
            # Nothing to reach them on. A booking taken over the counter may
            # have no usable number at all.
            customer_phone__gt='',
        )
        .exclude(
            notifications__kind=Notification.Kind.BOOKING_REMINDER,
        )
        .select_related('space__establishment')
    )

    # The send-after moment is per booking and wraps midnight, so it is
    # decided here rather than in SQL. The set is bounded by the lead time:
    # only bookings in the near future can be due.
    horizon = now + lead_time() + timedelta(days=1)
    return [
        reservation
        for reservation in candidates.filter(datetime__lte=horizon)
        if send_after(reservation) <= now
    ]


def reminder_text(reservation):
    """What the customer reads.

    Short on purpose: it is an SMS, it is read on a feature phone as often as
    not, and the only things that matter are which venue and what time.
    """
    when = timezone.localtime(reservation.datetime)
    venue = reservation.space.establishment.name
    return (
        f'Reminder: your table at {venue} is booked for '
        f'{when:%H:%M} today. See you soon.'
    )
