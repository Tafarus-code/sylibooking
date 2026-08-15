"""The seeded history, checked for the properties the screens depend on.

`seed_demo` is developer tooling, but the demo database is what every screen
is judged against before it ships — and a seed that quietly stops producing
no-shows takes the insights screen's no-show rate down with it, with nothing
failing anywhere. These assert the shape, not the exact numbers: the seed is
deterministic, but pinning counts would make it unchangeable rather than
correct.

Seeded once for the class. It is not a fast fixture, and every test here reads
the same database rather than needing its own.
"""

from datetime import timedelta
from itertools import pairwise

from django.conf import settings
from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone
from orders.models import Order

from establishments.models import Establishment, Review
from payments.models import Payment
from reservations.models import Reservation


class SeededHistoryTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        call_command('seed_demo', months=6, verbosity=0)

    def test_history_reaches_back_six_months(self):
        """The 90-day insights window has to land inside real data.

        Before this, the seed wrote 45 days — so the longest window a
        merchant can pick was half empty and looked like a bug.
        """
        oldest = Reservation.objects.order_by('datetime').first()

        age = timezone.now() - oldest.datetime

        self.assertGreater(age, timedelta(days=170))

    def test_every_month_of_the_window_has_bookings(self):
        """No gaps: a month-shaped hole in a chart reads as an outage."""
        now = timezone.now()
        for month in range(6):
            end = now - timedelta(days=30 * month)
            start = end - timedelta(days=30)

            booked = Reservation.objects.filter(
                datetime__gte=start, datetime__lt=end
            ).count()

            self.assertGreater(
                booked, 0, f'no bookings between {start:%Y-%m-%d} and {end:%Y-%m-%d}'
            )

    def test_missed_bookings_exist(self):
        """The insights no-show rate is null without these, forever.

        It is the one number the grace-period setting exists to move, and
        the seed produced none of them until the history did.
        """
        self.assertTrue(
            Reservation.objects.filter(
                status=Reservation.Status.NO_SHOW
            ).exists()
        )

    def test_some_customers_come_back(self):
        """Returning customers are counted by phone number.

        A history of one-off strangers reports every venue as having no
        regulars — false, and indistinguishable from a broken metric.
        """
        phones = (
            Reservation.objects.values_list('customer_phone', flat=True)
        )
        counts = {}
        for phone in phones:
            counts[phone] = counts.get(phone, 0) + 1

        returning = [phone for phone, seen in counts.items() if seen > 1]

        self.assertGreater(len(returning), 50)

    def test_no_two_bookings_hold_one_table_at_once(self):
        """The rule the API enforces, which bulk_create goes around.

        Seeded clashes would put two parties on one table on exactly the
        busy Saturday a merchant would look at first.

        Scoped to the history, which is what this generates. The near-term
        seeding has never checked itself and is left as it was found — the
        two overlap in time, so the generator loads existing bookings before
        placing any of its own.
        """
        duration = timedelta(minutes=settings.RESERVATION_DURATION_MINUTES)
        horizon = timezone.now() - timedelta(days=50)

        by_space = {}
        for space_id, when in (
            Reservation.objects.exclude(status=Reservation.Status.CANCELLED)
            .filter(datetime__lt=horizon)
            .values_list('space_id', 'datetime')
        ):
            by_space.setdefault(space_id, []).append(when)

        clashes = []
        for space_id, times in by_space.items():
            times.sort()
            for earlier, later in pairwise(times):
                if later - earlier < duration:
                    clashes.append((space_id, earlier, later))

        self.assertEqual(clashes, [])

    def test_payments_are_spread_across_the_window(self):
        """`created_at` is auto_now_add and bulk_create honours it.

        The CSV export filters payments by created_at, so if the backdating
        stopped working every historical export would come back empty while
        the screens above it still looked full.
        """
        oldest = Payment.objects.order_by('created_at').first()

        age = timezone.now() - oldest.created_at

        self.assertGreater(age, timedelta(days=150))

    def test_reviews_are_spread_across_the_window(self):
        oldest = Review.objects.order_by('created_at').first()

        age = timezone.now() - oldest.created_at

        self.assertGreater(age, timedelta(days=120))

    def test_orders_have_history_too(self):
        """Restaurants only, which is the standing rule."""
        old = Order.objects.filter(
            pickup_time__lt=timezone.now() - timedelta(days=150)
        )

        self.assertTrue(old.exists())
        self.assertFalse(
            old.filter(establishment__type=Establishment.Type.LOUNGE).exists()
        )

    def test_busy_nights_are_busier(self):
        """Fridays and Saturdays carry more than Mondays.

        Uniform data answers "which nights are worth opening for" with
        "all of them", which is the one answer that is never true.
        """
        weekends = weekdays = 0
        for (when,) in Reservation.objects.values_list('datetime'):
            local = timezone.localtime(when)
            if local.weekday() in (4, 5):
                weekends += 1
            elif local.weekday() in (0, 1):
                weekdays += 1

        self.assertGreater(weekends, weekdays)

    def test_today_still_has_something(self):
        """History must not have displaced the day a demo opens on."""
        today = timezone.localdate()

        self.assertTrue(
            Reservation.objects.filter(datetime__date=today).exists()
        )


class SeedIsRepeatableTests(TestCase):
    def test_running_twice_does_not_double_the_history(self):
        """Seeding is topped up, never doubled — the rule the rest of the
        command already follows."""
        call_command('seed_demo', months=1, verbosity=0)
        after_first = Reservation.objects.count()

        call_command('seed_demo', months=1, verbosity=0)

        # Today's sitting is topped up by design when it has lapsed; the
        # history behind it is not written twice.
        self.assertLess(Reservation.objects.count() - after_first, 100)

    def test_months_zero_skips_the_history(self):
        call_command('seed_demo', months=0, verbosity=0)

        oldest = Reservation.objects.order_by('datetime').first()

        self.assertLess(timezone.now() - oldest.datetime, timedelta(days=60))
