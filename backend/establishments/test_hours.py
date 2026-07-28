"""Opening hours, especially the overnight cases.

A lounge open until 02:00 is the ordinary case in Conakry, so "is it open?"
has to survive midnight. Every test pins a real moment rather than using
now(), so these do not pass or fail depending on when they run.
"""

from datetime import datetime, time

from django.test import TestCase
from django.utils import timezone

from .hours import (
    closing_time_at,
    is_open_at,
    todays_hours,
    week_schedule,
)
from .models import Establishment, OpeningHours

# 2026-08-03 is a Monday, which keeps the weekday arithmetic legible below.
MONDAY = datetime(2026, 8, 3)
TUESDAY = datetime(2026, 8, 4)
WEDNESDAY = datetime(2026, 8, 5)


def at(day, hour, minute=0):
    return timezone.make_aware(
        day.replace(hour=hour, minute=minute, second=0, microsecond=0)
    )


class HoursTestBase(TestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )

    def set_hours(self, day, opens=None, closes=None, is_closed=False):
        return OpeningHours.objects.create(
            establishment=self.establishment,
            day_of_week=day,
            is_closed=is_closed,
            opens=None if opens is None else time(*opens),
            closes=None if closes is None else time(*closes),
        )


class SameDayHoursTests(HoursTestBase):
    def setUp(self):
        super().setUp()
        # Monday 12:00-23:00, entirely within one day.
        self.set_hours(OpeningHours.Day.MONDAY, (12, 0), (23, 0))

    def test_open_during_the_interval(self):
        self.assertTrue(is_open_at(self.establishment, at(MONDAY, 15)))

    def test_closed_before_opening(self):
        self.assertFalse(is_open_at(self.establishment, at(MONDAY, 11)))

    def test_closed_after_closing(self):
        self.assertFalse(is_open_at(self.establishment, at(MONDAY, 23, 30)))

    def test_open_at_the_opening_minute(self):
        self.assertTrue(is_open_at(self.establishment, at(MONDAY, 12)))

    def test_closed_at_the_closing_minute(self):
        """23:00 close means last moment open is 22:59."""
        self.assertFalse(is_open_at(self.establishment, at(MONDAY, 23)))

    def test_closing_time_reported_while_open(self):
        self.assertEqual(
            closing_time_at(self.establishment, at(MONDAY, 15)), time(23, 0)
        )

    def test_no_closing_time_while_closed(self):
        self.assertIsNone(closing_time_at(self.establishment, at(MONDAY, 9)))


class OvernightHoursTests(HoursTestBase):
    """The case the whole model exists for: Monday 18:00 to 02:00."""

    def setUp(self):
        super().setUp()
        self.set_hours(OpeningHours.Day.MONDAY, (18, 0), (2, 0))

    def test_open_late_on_the_opening_day(self):
        self.assertTrue(is_open_at(self.establishment, at(MONDAY, 23)))

    def test_open_after_midnight_the_next_morning(self):
        """1am Tuesday is Monday's session still running."""
        self.assertTrue(is_open_at(self.establishment, at(TUESDAY, 1)))

    def test_closed_after_the_overnight_interval_ends(self):
        self.assertFalse(is_open_at(self.establishment, at(TUESDAY, 2, 30)))

    def test_closed_on_tuesday_evening_when_only_monday_is_set(self):
        """Tuesday has no hours of its own, so the venue is shut."""
        self.assertFalse(is_open_at(self.establishment, at(TUESDAY, 20)))

    def test_closed_before_monday_opening(self):
        self.assertFalse(is_open_at(self.establishment, at(MONDAY, 17)))

    def test_closing_time_after_midnight_comes_from_the_previous_day(self):
        self.assertEqual(
            closing_time_at(self.establishment, at(TUESDAY, 1)), time(2, 0)
        )

    def test_closing_time_before_midnight(self):
        self.assertEqual(
            closing_time_at(self.establishment, at(MONDAY, 23)), time(2, 0)
        )

    def test_monday_1am_needs_sundays_hours_not_mondays(self):
        """Monday 01:00 belongs to Sunday's session, if Sunday had one."""
        self.assertFalse(is_open_at(self.establishment, at(MONDAY, 1)))

        self.set_hours(OpeningHours.Day.SUNDAY, (18, 0), (3, 0))
        self.establishment.refresh_from_db()
        self.assertTrue(is_open_at(self.establishment, at(MONDAY, 1)))


class ClosedDayTests(HoursTestBase):
    def setUp(self):
        super().setUp()
        self.set_hours(OpeningHours.Day.MONDAY, is_closed=True)
        self.set_hours(OpeningHours.Day.TUESDAY, (12, 0), (23, 0))

    def test_a_closed_day_is_closed_all_day(self):
        for hour in [0, 9, 15, 21, 23]:
            with self.subTest(hour=hour):
                self.assertFalse(
                    is_open_at(self.establishment, at(MONDAY, hour))
                )

    def test_a_closed_day_does_not_borrow_another_days_hours(self):
        """The bug this guards: falling back to a day that is open."""
        self.assertFalse(is_open_at(self.establishment, at(MONDAY, 15)))
        self.assertTrue(is_open_at(self.establishment, at(TUESDAY, 15)))

    def test_todays_hours_reports_the_closed_row_not_a_neighbour(self):
        row = todays_hours(self.establishment, at(MONDAY, 15))
        self.assertIsNotNone(row)
        self.assertTrue(row.is_closed)
        self.assertEqual(row.day_of_week, OpeningHours.Day.MONDAY)


class MissingHoursTests(HoursTestBase):
    def test_an_establishment_with_no_hours_is_never_open(self):
        """Silence must not be read as "open"."""
        self.assertFalse(is_open_at(self.establishment, at(MONDAY, 15)))
        self.assertIsNone(todays_hours(self.establishment, at(MONDAY, 15)))

    def test_a_day_without_a_row_is_closed(self):
        self.set_hours(OpeningHours.Day.MONDAY, (12, 0), (23, 0))
        self.assertFalse(is_open_at(self.establishment, at(WEDNESDAY, 15)))

    def test_hours_with_no_times_are_treated_as_closed(self):
        self.set_hours(OpeningHours.Day.MONDAY, opens=None, closes=None)
        self.assertFalse(is_open_at(self.establishment, at(MONDAY, 15)))


class WeekScheduleTests(HoursTestBase):
    def test_always_seven_days_in_order(self):
        self.set_hours(OpeningHours.Day.FRIDAY, (18, 0), (2, 0))

        week = week_schedule(self.establishment)

        self.assertEqual([row.day_of_week for row in week], list(range(7)))

    def test_unset_days_come_back_as_closed(self):
        self.set_hours(OpeningHours.Day.FRIDAY, (18, 0), (2, 0))

        week = week_schedule(self.establishment)

        self.assertFalse(week[OpeningHours.Day.FRIDAY].is_closed)
        self.assertTrue(week[OpeningHours.Day.MONDAY].is_closed)


class OpeningHoursModelTests(HoursTestBase):
    def test_str_of_an_open_day(self):
        row = self.set_hours(OpeningHours.Day.MONDAY, (18, 0), (2, 0))
        self.assertEqual(str(row), 'Monday: 18:00-02:00')

    def test_str_of_a_closed_day(self):
        row = self.set_hours(OpeningHours.Day.MONDAY, is_closed=True)
        self.assertEqual(str(row), 'Monday: closed')

    def test_runs_past_midnight_detection(self):
        overnight = self.set_hours(OpeningHours.Day.MONDAY, (18, 0), (2, 0))
        same_day = self.set_hours(OpeningHours.Day.TUESDAY, (12, 0), (23, 0))

        self.assertTrue(overnight.runs_past_midnight)
        self.assertFalse(same_day.runs_past_midnight)

    def test_one_row_per_day_per_establishment(self):
        from django.db import IntegrityError, transaction

        self.set_hours(OpeningHours.Day.MONDAY, (12, 0), (23, 0))
        with self.assertRaises(IntegrityError), transaction.atomic():
            self.set_hours(OpeningHours.Day.MONDAY, (14, 0), (22, 0))
