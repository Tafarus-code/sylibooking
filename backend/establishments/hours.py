"""Answering "is it open right now?" from a week of opening hours.

Computed server-side so both apps agree, and so the overnight arithmetic —
which is where this gets fiddly — exists once rather than once per client.
"""

from datetime import timedelta

from django.utils import timezone

from .models import OpeningHours


def hours_by_day(establishment):
    """The establishment's rows keyed by weekday, using any prefetch."""
    return {row.day_of_week: row for row in establishment.hours.all()}


def hours_for(establishment, day):
    """The row governing ``day`` (a date), or None if none is recorded."""
    return hours_by_day(establishment).get(day.weekday())


def is_open_at(establishment, moment=None):
    """Whether ``establishment`` is open at ``moment``.

    Two rows can be responsible: today's, and yesterday's if it ran past
    midnight. A lounge open Monday 18:00-02:00 is open at Tuesday 01:00, and
    only Monday's row knows that.
    """
    moment = timezone.localtime(moment or timezone.now())
    rows = hours_by_day(establishment)
    today = moment.date()
    time_of_day = moment.time()

    todays = rows.get(today.weekday())
    if todays is not None and todays.covers(time_of_day):
        return True

    yesterday = today - timedelta(days=1)
    yesterdays = rows.get(yesterday.weekday())
    return yesterdays is not None and yesterdays.covers(
        time_of_day, from_previous_day=True
    )


def closing_time_at(establishment, moment=None):
    """When the current opening interval ends, or None if closed.

    Used for "Open until 23:00", so it must report the closing time of the
    interval actually in progress — which after midnight is yesterday's.
    """
    moment = timezone.localtime(moment or timezone.now())
    rows = hours_by_day(establishment)
    today = moment.date()
    time_of_day = moment.time()

    todays = rows.get(today.weekday())
    if todays is not None and todays.covers(time_of_day):
        return todays.closes

    yesterday = today - timedelta(days=1)
    yesterdays = rows.get(yesterday.weekday())
    if yesterdays is not None and yesterdays.covers(
        time_of_day, from_previous_day=True
    ):
        return yesterdays.closes
    return None


def todays_hours(establishment, moment=None):
    """The row for the current local day, whether or not it is open now.

    Deliberately the *current* day and nothing else: falling back to another
    day's hours, or to a default, would tell a customer a venue is open when
    it is shut.
    """
    moment = timezone.localtime(moment or timezone.now())
    return hours_by_day(establishment).get(moment.date().weekday())


def week_schedule(establishment):
    """All seven days in order, with a placeholder for any day not recorded.

    The customer app shows a full week, so a venue that has only filled in
    five days must still render seven rows rather than a ragged list.
    """
    rows = hours_by_day(establishment)
    return [
        rows.get(day)
        or OpeningHours(
            establishment=establishment, day_of_week=day, is_closed=True
        )
        for day in range(7)
    ]
