"""Reminders, and the record that they were sent.

The queue slice proved work reaches a worker. This one is about whether the
right work reaches the right customer, once — and about the log row, because
"did the customer get the reminder?" is the first question a merchant asks
when somebody does not turn up, and until now it had no answer.

Everything runs eagerly. What is being tested is the rule, not the transport.
"""

from datetime import timedelta
from unittest import mock

from accounts.notifications import NotificationError
from celery.exceptions import Retry
from django.core.management import call_command
from django.test import override_settings
from django.utils import timezone
from orders.models import Order
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space
from notifications.models import Notification
from notifications.reminders import (
    due_reservations,
    is_quiet,
    reminder_text,
    send_after,
)
from notifications.tasks import (
    queue_due_reminders,
    send_booking_reminder,
    sweep_no_shows,
)
from reservations.models import Reservation

EAGER = override_settings(CELERY_TASK_ALWAYS_EAGER=True)

#: Quiet hours turned off, so "is this reminder due?" does not depend on what
#: time the suite happens to run at.
#:
#: A booking three hours out is due — unless sending it would land between
#: 22:00 and 07:00, in which case it waits for morning and is correctly not
#: due. That is the behaviour QuietHoursTests exists to check; everywhere
#: else it is a way for the suite to pass all day and fail overnight.
#: An empty window (start == end) is never quiet.
NO_QUIET = override_settings(
    REMINDER_QUIET_START='00:00', REMINDER_QUIET_END='00:00'
)


class ReminderTestBase(APITestCase):
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

    def book(
        self,
        when=None,
        status=Reservation.Status.CONFIRMED,
        phone='+224620000000',
    ):
        return Reservation.objects.create(
            space=self.table,
            customer_name='Mariama',
            customer_phone=phone,
            datetime=when or (timezone.now() + timedelta(hours=4)),
            party_size=2,
            status=status,
        )

    def at_local(self, hour, days=0):
        """A booking time at a given local hour, so quiet hours are testable
        without depending on when the suite happens to run."""
        local = timezone.localtime(timezone.now()) + timedelta(days=days)
        return local.replace(hour=hour, minute=0, second=0, microsecond=0)


class QuietHoursTests(ReminderTestBase):
    def test_the_middle_of_the_night_is_quiet(self):
        self.assertTrue(is_quiet(self.at_local(3)))

    def test_the_evening_is_not(self):
        self.assertFalse(is_quiet(self.at_local(19)))

    def test_the_window_wraps_midnight(self):
        """22:00–07:00 is one window, not two comparisons that miss."""
        self.assertTrue(is_quiet(self.at_local(23)))
        self.assertTrue(is_quiet(self.at_local(5)))
        self.assertFalse(is_quiet(self.at_local(12)))

    def test_a_reminder_due_in_the_evening_goes_out_then(self):
        booking = self.book(when=self.at_local(21, days=1))

        # 21:00 less a three-hour lead is 18:00, which is nobody's bedtime.
        self.assertEqual(
            timezone.localtime(send_after(booking)).hour, 18
        )

    def test_a_reminder_that_would_land_at_dawn_waits_for_morning(self):
        """A 09:00 booking less three hours is 06:00. A phone ringing then is
        worse than a reminder with less notice."""
        booking = self.book(when=self.at_local(9, days=1))

        sent_at = timezone.localtime(send_after(booking))

        self.assertEqual(sent_at.hour, 7)
        self.assertFalse(is_quiet(sent_at))

    def test_it_still_arrives_before_the_booking(self):
        booking = self.book(when=self.at_local(9, days=1))

        self.assertLess(send_after(booking), booking.datetime)


@NO_QUIET
class DueTests(ReminderTestBase):
    def test_a_booking_far_off_is_not_due_yet(self):
        self.book(when=timezone.now() + timedelta(days=3))

        self.assertEqual(due_reservations(), [])

    def test_a_booking_inside_the_lead_time_is_due(self):
        booking = self.book(when=timezone.now() + timedelta(hours=2))

        self.assertEqual([r.pk for r in due_reservations()], [booking.pk])

    def test_a_cancelled_booking_is_never_reminded(self):
        """Reminding somebody about a table they cancelled is worse than
        saying nothing at all."""
        self.book(
            when=timezone.now() + timedelta(hours=2),
            status=Reservation.Status.CANCELLED,
        )

        self.assertEqual(due_reservations(), [])

    def test_a_booking_in_the_past_is_not_reminded(self):
        self.book(when=timezone.now() - timedelta(hours=1))

        self.assertEqual(due_reservations(), [])

    def test_a_booking_with_no_number_is_skipped(self):
        """Taken over the counter, with nothing to reach them on."""
        self.book(when=timezone.now() + timedelta(hours=2), phone='')

        self.assertEqual(due_reservations(), [])

    def test_a_booking_already_reminded_is_not_due_again(self):
        booking = self.book(when=timezone.now() + timedelta(hours=2))
        Notification.objects.create(
            kind=Notification.Kind.BOOKING_REMINDER,
            reservation=booking,
            destination=booking.customer_phone,
            status=Notification.Status.SENT,
        )

        self.assertEqual(due_reservations(), [])

    def test_the_text_names_the_venue_and_the_time(self):
        booking = self.book(when=self.at_local(20))

        text = reminder_text(booking)

        self.assertIn('Le Petit Baobab', text)
        self.assertIn('20:00', text)


@EAGER
class SendingTests(ReminderTestBase):
    def test_sending_writes_a_log_row(self):
        """The answer to "did they get it", which did not exist before."""
        booking = self.book(when=timezone.now() + timedelta(hours=2))

        send_booking_reminder(booking.pk)

        notification = Notification.objects.get(reservation=booking)
        self.assertEqual(notification.status, Notification.Status.SENT)
        self.assertEqual(notification.destination, '+224620000000')
        self.assertEqual(notification.error, '')

    def test_a_booking_cancelled_after_queueing_is_not_reminded(self):
        """The gap between queueing and running is the whole point of a
        queue, so the task re-reads rather than trusting what it was given.
        """
        booking = self.book(when=timezone.now() + timedelta(hours=2))
        booking.status = Reservation.Status.CANCELLED
        booking.save(update_fields=['status'])

        result = send_booking_reminder(booking.pk)

        self.assertEqual(result, 'not open')
        self.assertFalse(Notification.objects.exists())

    def test_a_deleted_booking_does_not_retry_for_ever(self):
        booking = self.book(when=timezone.now() + timedelta(hours=2))
        pk = booking.pk
        booking.delete()

        self.assertEqual(send_booking_reminder(pk), 'gone')

    def test_the_same_reminder_is_never_sent_twice(self):
        """A scheduler fires repeatedly; the database is what stops it."""
        booking = self.book(when=timezone.now() + timedelta(hours=2))

        send_booking_reminder(booking.pk)
        second = send_booking_reminder(booking.pk)

        self.assertEqual(second, 'already sent')
        self.assertEqual(
            Notification.objects.filter(reservation=booking).count(), 1
        )

    def test_a_gateway_failure_is_recorded_rather_than_lost(self):
        booking = self.book(when=timezone.now() + timedelta(hours=2))

        with mock.patch(
            'notifications.tasks.get_notifier'
        ) as get_notifier:
            get_notifier.return_value.send.side_effect = _gateway_down()
            with self.assertRaises((Retry, NotificationError)):
                send_booking_reminder(booking.pk)

        notification = Notification.objects.get(reservation=booking)
        self.assertEqual(notification.status, Notification.Status.FAILED)
        self.assertIn('gateway', notification.error)

    def test_a_gateway_failure_does_not_touch_the_booking(self):
        """A notifier raising must not lose the table."""
        booking = self.book(when=timezone.now() + timedelta(hours=2))

        with mock.patch('notifications.tasks.get_notifier') as get_notifier:
            get_notifier.return_value.send.side_effect = _gateway_down()
            with self.assertRaises((Retry, NotificationError)):
                send_booking_reminder(booking.pk)

        booking.refresh_from_db()
        self.assertEqual(booking.status, Reservation.Status.CONFIRMED)


@EAGER
@NO_QUIET
class BeatTests(ReminderTestBase):
    def test_the_sweep_queues_one_task_per_due_booking(self):
        self.book(when=timezone.now() + timedelta(hours=2))
        self.book(when=timezone.now() + timedelta(hours=2, minutes=30))

        self.assertEqual(queue_due_reminders(), 2)
        self.assertEqual(Notification.objects.count(), 2)

    def test_running_the_beat_twice_sends_one_reminder_each(self):
        """**The property a scheduler makes necessary.**

        Beat fires every few minutes. Without the constraint in the database
        every customer would be reminded on every tick.
        """
        booking = self.book(when=timezone.now() + timedelta(hours=2))

        queue_due_reminders()
        queue_due_reminders()

        self.assertEqual(
            Notification.objects.filter(reservation=booking).count(), 1
        )

    def test_the_no_show_sweep_runs_on_the_schedule_too(self):
        """Slice 4 said the lapse command would move onto the scheduler."""
        missed = self.book(when=timezone.now() - timedelta(minutes=200))

        sweep_no_shows()

        missed.refresh_from_db()
        self.assertEqual(missed.status, Reservation.Status.NO_SHOW)

    def test_the_command_still_works_by_hand(self):
        """The task wraps it rather than replacing it: --dry-run is still how
        you see what would happen."""
        missed = self.book(when=timezone.now() - timedelta(minutes=200))

        call_command('lapse_no_shows', '--dry-run', verbosity=0)

        missed.refresh_from_db()
        self.assertEqual(missed.status, Reservation.Status.CONFIRMED)


@EAGER
class OrderReadyTests(ReminderTestBase):
    def setUp(self):
        super().setUp()
        self.restaurant = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Kaloum',
        )

    def order(self, phone='+224620000000'):
        return Order.objects.create(
            establishment=self.restaurant,
            customer_name='Mariama',
            customer_phone=phone,
            pickup_time=timezone.now() + timedelta(hours=1),
        )

    def test_a_ready_order_tells_the_customer(self):
        from notifications.tasks import send_order_ready

        order = self.order()

        send_order_ready(order.pk)

        notification = Notification.objects.get(order=order)
        self.assertEqual(notification.kind, Notification.Kind.ORDER_READY)
        self.assertEqual(notification.status, Notification.Status.SENT)

    def test_it_is_only_said_once(self):
        from notifications.tasks import send_order_ready

        order = self.order()

        send_order_ready(order.pk)
        self.assertEqual(send_order_ready(order.pk), 'already sent')

    def test_an_order_with_no_number_is_skipped(self):
        from notifications.tasks import send_order_ready

        order = self.order(phone='')

        self.assertEqual(send_order_ready(order.pk), 'no destination')
        self.assertFalse(Notification.objects.exists())


def _gateway_down():
    return NotificationError('gateway down')


class ActivityEndpointTests(ReminderTestBase):
    """What the desk polls to find out that something arrived.

    Counts only: the app already knows how to fetch the lists, it just has no
    reason to until this says so.
    """

    def setUp(self):
        super().setUp()
        from django.contrib.auth.models import User
        from rest_framework.authtoken.models import Token

        from establishments.models import MerchantMembership

        self.owner = User.objects.create_user('amadou', password='pw-for-tests')
        MerchantMembership.objects.create(
            user=self.owner,
            establishment=self.venue,
            role=MerchantMembership.Role.OWNER,
        )
        token, _ = Token.objects.get_or_create(user=self.owner)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def ask(self, since=None, establishment=None):
        from django.urls import reverse

        params = {'establishment': (establishment or self.venue).pk}
        if since is not None:
            params['since'] = since.isoformat()
        return self.client.get(reverse('merchant-activity'), params)

    def test_nothing_new_is_zero(self):
        response = self.ask(since=timezone.now())

        self.assertEqual(response.data['total'], 0)

    def test_a_booking_taken_since_is_counted(self):
        self.book(when=timezone.now() + timedelta(hours=5))

        response = self.ask(since=timezone.now() - timedelta(minutes=5))

        self.assertEqual(response.data['reservations'], 1)
        self.assertEqual(response.data['total'], 1)

    def test_a_booking_taken_before_is_not(self):
        booking = self.book(when=timezone.now() + timedelta(hours=5))
        Reservation.objects.filter(pk=booking.pk).update(
            created_at=timezone.now() - timedelta(hours=2)
        )

        response = self.ask(since=timezone.now() - timedelta(minutes=5))

        self.assertEqual(response.data['total'], 0)

    def test_without_a_since_the_answer_is_zero(self):
        """A client that has not said where it got to is not asking a
        question we can answer."""
        self.book(when=timezone.now() + timedelta(hours=5))

        response = self.ask()

        self.assertEqual(response.data['total'], 0)

    def test_another_venues_work_is_not_counted(self):
        other = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre',
        )
        table = Space.objects.create(
            establishment=other, name='Table 1', capacity=2
        )
        Reservation.objects.create(
            space=table,
            customer_name='Someone',
            customer_phone='+224620000009',
            datetime=timezone.now() + timedelta(hours=5),
            party_size=2,
        )

        response = self.ask(since=timezone.now() - timedelta(minutes=5))

        self.assertEqual(response.data['total'], 0)

    def test_a_non_member_is_told_nothing(self):
        from django.contrib.auth.models import User
        from rest_framework.authtoken.models import Token

        outsider = User.objects.create_user('nobody', password='pw-for-tests')
        token, _ = Token.objects.get_or_create(user=outsider)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        response = self.ask(since=timezone.now())

        self.assertEqual(response.status_code, 404)

    def test_a_signed_out_caller_is_refused(self):
        self.client.credentials()

        response = self.ask(since=timezone.now())

        self.assertEqual(response.status_code, 401)

    def test_a_nonsense_since_does_not_500(self):
        from django.urls import reverse

        response = self.client.get(
            reverse('merchant-activity'),
            {'establishment': self.venue.pk, 'since': 'yesterday-ish'},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['total'], 0)
