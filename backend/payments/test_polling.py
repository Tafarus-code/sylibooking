"""Chasing payments nobody is watching.

Before this, the only thing that ever asked a provider "did it go through?"
was the customer's own screen — which stops the moment they lock their phone,
which is exactly when they are approving the prompt. Against the mock that was
latency. Against a real provider it is a paid booking left unconfirmed and a
merchant turning away a table that was paid for.

These run against the mock, which is what the real adapter will be dropped
into, so the poller Slice 11 inherits is one that has already been exercised.
"""

from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.test import override_settings
from django.utils import timezone
from notifications.tasks import poll_pending_payments
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space
from payments.models import Payment
from payments.polling import abandoned, due_for_poll, poll_interval
from payments.providers import PaymentError
from reservations.models import Reservation

EAGER = override_settings(CELERY_TASK_ALWAYS_EAGER=True)


class PollingTestBase(APITestCase):
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

    def booking(self, status=Reservation.Status.PENDING):
        return Reservation.objects.create(
            space=self.table,
            customer_name='Mariama',
            customer_phone='+224620000000',
            datetime=timezone.now() + timedelta(hours=4),
            party_size=2,
            status=status,
        )

    def payment(
        self,
        *,
        reservation=None,
        status=Payment.Status.PENDING,
        age=timedelta(0),
        polled_ago=None,
        reference='MOCK-PENDING-1',
    ):
        payment = Payment.objects.create(
            reservation=reservation or self.booking(),
            provider=Payment.Provider.ORANGE_MONEY,
            amount=Decimal('50000.00'),
            status=status,
            provider_reference=reference,
        )
        now = timezone.now()
        updates = {'created_at': now - age}
        if polled_ago is not None:
            updates['last_polled_at'] = now - polled_ago
        Payment.objects.filter(pk=payment.pk).update(**updates)
        payment.refresh_from_db()
        return payment


class IntervalTests(PollingTestBase):
    def test_a_fresh_payment_is_asked_about_often(self):
        self.assertEqual(
            poll_interval(timedelta(seconds=30)), timedelta(seconds=15)
        )

    def test_a_few_minutes_in_it_slows_down(self):
        self.assertEqual(
            poll_interval(timedelta(minutes=5)), timedelta(minutes=1)
        )

    def test_an_old_one_is_barely_chased(self):
        """Hammering the provider for a payment nobody approved costs rate
        limit that a fresh payment needs."""
        self.assertEqual(
            poll_interval(timedelta(minutes=20)), timedelta(minutes=5)
        )

    def test_the_interval_never_shrinks_with_age(self):
        ages = [timedelta(seconds=1), timedelta(minutes=3), timedelta(hours=1)]
        intervals = [poll_interval(age) for age in ages]

        self.assertEqual(intervals, sorted(intervals))


class DueTests(PollingTestBase):
    def test_a_never_polled_payment_is_due_immediately(self):
        payment = self.payment()

        self.assertEqual([p.pk for p in due_for_poll()], [payment.pk])

    def test_one_just_polled_is_not_due_again(self):
        self.payment(polled_ago=timedelta(seconds=2))

        self.assertEqual(due_for_poll(), [])

    def test_it_becomes_due_once_its_interval_passes(self):
        payment = self.payment(polled_ago=timedelta(seconds=20))

        self.assertEqual([p.pk for p in due_for_poll()], [payment.pk])

    def test_a_settled_payment_is_never_polled(self):
        """Terminal is terminal; asking again cannot change it."""
        self.payment(status=Payment.Status.COMPLETED)
        self.payment(status=Payment.Status.FAILED, reference='MOCK-FAILED-1')

        self.assertEqual(due_for_poll(), [])

    def test_a_payment_with_no_provider_reference_is_skipped(self):
        """Initiation failed, so there is nothing to ask about."""
        self.payment(reference='')

        self.assertEqual(due_for_poll(), [])

    def test_a_payment_past_giving_up_is_not_polled_any_more(self):
        self.payment(age=timedelta(minutes=45))

        self.assertEqual(due_for_poll(), [])


@EAGER
class PollerTests(PollingTestBase):
    def test_a_payment_that_completed_unwatched_is_noticed(self):
        """**The whole point.** Nobody has the screen open; the mock says it
        went through; the booking must end up confirmed anyway."""
        booking = self.booking()
        self.payment(reservation=booking)

        poll_pending_payments()

        booking.refresh_from_db()
        self.assertEqual(booking.status, Reservation.Status.CONFIRMED)
        self.assertEqual(
            booking.payments.first().status, Payment.Status.COMPLETED
        )

    def test_it_confirms_the_same_way_the_customer_screen_does(self):
        """Two paths to one outcome; they must not disagree."""
        watched = self.booking()
        watched_payment = self.payment(reservation=watched)
        unwatched = self.booking()
        self.payment(reservation=unwatched, reference='MOCK-PENDING-2')

        from payments.services import refresh_payment

        refresh_payment(watched_payment)
        poll_pending_payments()

        watched.refresh_from_db()
        unwatched.refresh_from_db()
        self.assertEqual(watched.status, unwatched.status)
        self.assertEqual(watched.status, Reservation.Status.CONFIRMED)

    def test_polling_records_that_it_asked(self):
        payment = self.payment()

        poll_pending_payments()

        payment.refresh_from_db()
        self.assertIsNotNone(payment.last_polled_at)

    def test_an_unreachable_provider_leaves_it_pending_for_next_time(self):
        payment = self.payment()

        with mock.patch(
            'payments.services.get_payment_provider'
        ) as get_provider:
            get_provider.return_value.check_status.side_effect = PaymentError(
                'gateway timeout'
            )
            poll_pending_payments()

        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.PENDING)

    def test_one_bad_provider_does_not_stop_the_others_being_chased(self):
        """A per-payment failure is per payment."""
        first = self.payment(reference='MOCK-A')
        second = self.payment(reference='MOCK-B')

        poll_pending_payments()

        first.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual(first.status, Payment.Status.COMPLETED)
        self.assertEqual(second.status, Payment.Status.COMPLETED)

    def test_an_order_payment_is_chased_too(self):
        """An order's money goes stale in exactly the same way."""
        from orders.models import Order

        restaurant = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Kaloum',
        )
        order = Order.objects.create(
            establishment=restaurant,
            customer_name='Mariama',
            customer_phone='+224620000000',
            pickup_time=timezone.now() + timedelta(hours=2),
        )
        payment = Payment.objects.create(
            order=order,
            provider=Payment.Provider.ORANGE_MONEY,
            amount=Decimal('75000.00'),
            status=Payment.Status.PENDING,
            provider_reference='MOCK-ORDER-1',
        )

        poll_pending_payments()

        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.COMPLETED)


@EAGER
class GivingUpTests(PollingTestBase):
    def test_a_payment_nobody_approved_is_written_off(self):
        payment = self.payment(age=timedelta(minutes=45))

        poll_pending_payments()

        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.FAILED)

    def test_a_young_payment_is_left_alone(self):
        payment = self.payment(age=timedelta(minutes=5), status=Payment.Status.PENDING)

        with mock.patch(
            'payments.services.get_payment_provider'
        ) as get_provider:
            get_provider.return_value.check_status.return_value = (
                Payment.Status.PENDING
            )
            poll_pending_payments()

        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.PENDING)

    def test_the_booking_is_left_for_the_merchant_to_deal_with(self):
        """Writing the payment off is not the same as cancelling the table.

        The merchant sees an unpaid booking and decides — the server refuses
        to confirm it, which is the existing rule and enough.
        """
        booking = self.booking()
        self.payment(reservation=booking, age=timedelta(minutes=45))

        poll_pending_payments()

        booking.refresh_from_db()
        self.assertEqual(booking.status, Reservation.Status.PENDING)

    @override_settings(PAYMENT_ABANDON_AFTER_MINUTES=5)
    def test_the_window_is_configurable(self):
        payment = self.payment(age=timedelta(minutes=6))

        self.assertEqual([p.pk for p in abandoned()], [payment.pk])

    def test_giving_up_twice_changes_nothing(self):
        """The beat runs every thirty seconds."""
        payment = self.payment(age=timedelta(minutes=45))

        poll_pending_payments()
        poll_pending_payments()

        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.FAILED)
        self.assertEqual(
            Payment.objects.filter(status=Payment.Status.FAILED).count(), 1
        )
