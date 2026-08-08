"""Finding out from a dashboard rather than from a merchant.

Three things get exercised here: the two health endpoints answer the two
different questions asked of them, the metrics say what actually happened in
a window, and the error reporter never becomes the reason an error is lost.
"""

import json
import logging
from datetime import timedelta
from decimal import Decimal

from config.errors import LoggingReporter, report
from config.logging import JsonFormatter
from django.contrib.auth.models import User
from django.core.cache import cache
from django.test import SimpleTestCase, TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from notifications.models import Notification
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space
from payments.models import Payment
from reservations.models import Reservation


class LivenessTests(APITestCase):
    def test_it_answers_without_touching_anything(self):
        """A liveness probe that checks the database restarts a healthy web
        server because Postgres hiccuped — one outage becomes two."""
        with self.assertNumQueries(0):
            response = self.client.get(reverse('health'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'ok')

    def test_it_needs_no_account(self):
        """A balancer has no credentials and never will."""
        response = self.client.get(reverse('health'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class ReadinessTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)

    def test_a_healthy_deployment_says_ok(self):
        response = self.client.get(reverse('health-ready'))

        # The broker is not running in the suite, so only assert the parts
        # this process can actually satisfy.
        self.assertIn('database', response.data['checks'])
        self.assertTrue(response.data['checks']['database']['ok'])
        self.assertTrue(response.data['checks']['cache']['ok'])

    def test_every_part_is_named(self):
        """The 503 is what wakes somebody; "which one" is their first
        question."""
        response = self.client.get(reverse('health-ready'))

        self.assertEqual(
            set(response.data['checks']),
            {'database', 'cache', 'broker'},
        )

    def test_one_broken_part_does_not_hide_the_others(self):
        """**The rule this endpoint exists for.** Knowing the database is
        fine while the broker is gone is most of the diagnosis."""

        def explode():
            raise RuntimeError('broker unreachable')

        with self.settings():
            from api import health

            original = health.CHECKS['broker']
            health.CHECKS['broker'] = explode
            self.addCleanup(lambda: health.CHECKS.__setitem__('broker', original))

            response = self.client.get(reverse('health-ready'))

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['status'], 'degraded')
        self.assertFalse(response.data['checks']['broker']['ok'])
        # And the healthy ones still report healthy.
        self.assertTrue(response.data['checks']['database']['ok'])

    def test_the_failure_is_described(self):
        def explode():
            raise RuntimeError('broker unreachable')

        from api import health

        original = health.CHECKS['broker']
        health.CHECKS['broker'] = explode
        self.addCleanup(lambda: health.CHECKS.__setitem__('broker', original))

        response = self.client.get(reverse('health-ready'))

        self.assertIn('unreachable', response.data['checks']['broker']['error'])


class MetricsTests(APITestCase):
    def setUp(self):
        self.venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.table = Space.objects.create(
            establishment=self.venue, name='Table 4', capacity=4
        )
        self.admin = User.objects.create_superuser(
            'root', 'root@example.com', 'pw-for-tests'
        )

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def booking(self, status_=Reservation.Status.CONFIRMED):
        return Reservation.objects.create(
            space=self.table,
            customer_name='Mariama',
            customer_phone='+224620000000',
            datetime=timezone.now() + timedelta(hours=3),
            party_size=2,
            status=status_,
        )

    def payment(self, state):
        return Payment.objects.create(
            reservation=self.booking(),
            provider=Payment.Provider.ORANGE_MONEY,
            amount=Decimal('50000.00'),
            status=state,
            provider_reference=f'REF-{state}',
        )

    def get(self, **params):
        self.authenticate(self.admin)
        return self.client.get(reverse('metrics'), params)

    def test_it_is_admin_only(self):
        """How much money moved and how many people came is a venue's
        business, and in aggregate the platform's trading position."""
        staff = User.objects.create_user('amadou', password='pw-for-tests')
        self.authenticate(staff)

        response = self.client.get(reverse('metrics'))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_bookings_are_counted(self):
        self.booking()
        self.booking()

        self.assertEqual(self.get().data['bookings']['created'], 2)

    def test_no_shows_are_counted_separately(self):
        """A jump here is either a bad night or a window set too tight."""
        self.booking()
        self.booking(Reservation.Status.NO_SHOW)

        data = self.get().data['bookings']
        self.assertEqual(data['created'], 2)
        self.assertEqual(data['no_show'], 1)

    def test_the_payment_completion_rate_is_the_number_to_watch(self):
        """**The gap money falls through.** A prompt that never resolves is
        a customer who tried to pay and could not."""
        self.payment(Payment.Status.COMPLETED)
        self.payment(Payment.Status.COMPLETED)
        self.payment(Payment.Status.COMPLETED)
        self.payment(Payment.Status.FAILED)

        data = self.get().data['payments']
        self.assertEqual(data['started'], 4)
        self.assertEqual(data['completed'], 3)
        self.assertEqual(data['completion_rate'], 0.75)

    def test_a_quiet_window_has_no_rate_rather_than_a_rate_of_zero(self):
        """Zero would mean every payment failed. Nothing happened is not the
        same alarm."""
        self.assertIsNone(self.get().data['payments']['completion_rate'])

    def test_the_notification_delivery_rate_is_visible(self):
        """Silent by construction: nobody complains about a reminder they
        never expected. Slice 7's log exists so this can be read at all."""
        booking = self.booking()
        Notification.objects.create(
            kind=Notification.Kind.BOOKING_REMINDER,
            reservation=booking,
            destination='+224620000000',
            status=Notification.Status.SENT,
        )
        Notification.objects.create(
            kind=Notification.Kind.ORDER_READY,
            reservation=self.booking(),
            destination='+224620000001',
            status=Notification.Status.FAILED,
        )

        data = self.get().data['notifications']
        self.assertEqual(data['attempted'], 2)
        self.assertEqual(data['sent'], 1)
        self.assertEqual(data['delivery_rate'], 0.5)

    def test_the_window_excludes_what_is_older_than_it(self):
        """A lifetime total hides today, and today is what anybody acts on."""
        old = self.booking()
        Reservation.objects.filter(pk=old.pk).update(
            created_at=timezone.now() - timedelta(days=3)
        )
        self.booking()

        self.assertEqual(self.get(hours=24).data['bookings']['created'], 1)

    def test_a_wider_window_can_be_asked_for(self):
        old = self.booking()
        Reservation.objects.filter(pk=old.pk).update(
            created_at=timezone.now() - timedelta(days=3)
        )
        self.booking()

        self.assertEqual(self.get(hours=24 * 7).data['bookings']['created'], 2)

    def test_an_absurd_window_is_clamped_rather_than_refused(self):
        self.assertLessEqual(self.get(hours=99999).data['window']['hours'], 24 * 30)

    def test_nonsense_falls_back_to_the_default(self):
        self.assertEqual(self.get(hours='soon').data['window']['hours'], 24)


class JsonLoggingTests(SimpleTestCase):
    def line(self, record):
        return json.loads(JsonFormatter().format(record))

    def record(self, message='hello', **extra):
        record = logging.LogRecord(
            'sylibooking', logging.INFO, __file__, 1, message, None, None
        )
        for key, value in extra.items():
            setattr(record, key, value)
        return record

    def test_a_line_is_one_json_object(self):
        parsed = self.line(self.record())

        self.assertEqual(parsed['message'], 'hello')
        self.assertEqual(parsed['level'], 'INFO')
        self.assertEqual(parsed['logger'], 'sylibooking')

    def test_what_a_caller_attached_travels_with_the_message(self):
        """**What makes a log line queryable.** reservation=41 rather than
        "…for booking 41" buried in a sentence."""
        parsed = self.line(self.record(reservation=41, provider='mtn'))

        self.assertEqual(parsed['reservation'], 41)
        self.assertEqual(parsed['provider'], 'mtn')

    def test_an_exception_comes_with_its_traceback(self):
        try:
            raise ValueError('nope')
        except ValueError:
            import sys

            record = self.record('failed')
            record.exc_info = sys.exc_info()

        parsed = self.line(record)

        self.assertIn('ValueError', parsed['exception'])

    def test_something_unserialisable_does_not_break_the_line(self):
        """A formatter that throws while reporting a failure loses the
        failure."""
        parsed = self.line(self.record(thing=object()))

        self.assertIsInstance(parsed['thing'], str)


class ErrorReporterTests(TestCase):
    def test_with_no_dsn_it_writes_to_the_log(self):
        """Not a degraded mode — the normal one locally and in CI, and the
        log is shipped and indexed in production anyway."""
        from config import errors

        errors._reporter = None
        self.addCleanup(lambda: setattr(errors, '_reporter', None))

        self.assertIsInstance(errors.get_reporter(), LoggingReporter)

    def test_reporting_never_raises(self):
        """**The rule.** A reporter that can throw turns one failure into
        two, and the second has no reporter left to catch it."""
        from config import errors

        class Broken:
            def capture(self, error, **context):
                raise RuntimeError('the reporter is down')

        errors._reporter = Broken()
        self.addCleanup(lambda: setattr(errors, '_reporter', None))

        with self.assertLogs('config.errors', level='ERROR'):
            report(ValueError('original problem'))  # must not raise

    @override_settings(SENTRY_DSN='https://not-a-real-dsn.example/1')
    def test_a_broken_sentry_falls_back_rather_than_losing_the_error(self):
        """A missing package or a malformed DSN must not be the reason an
        error goes unreported."""
        from config import errors

        errors._reporter = None
        self.addCleanup(lambda: setattr(errors, '_reporter', None))

        reporter = errors.get_reporter()

        # Either Sentry started, or it did not and the log took over. What
        # must never happen is no reporter at all.
        self.assertIsNotNone(reporter)
        self.assertTrue(hasattr(reporter, 'capture'))
