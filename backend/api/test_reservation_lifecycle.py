"""Bookings reaching an end state, and the grace period they are judged by.

Until this existed, `completed` was a status nothing ever set: a confirmed
booking stayed confirmed for ever, its slot was held for ever, and "past
bookings" were past only by date.

The property worth reading carefully is that a booking is judged against the
window it was *taken* under, not the venue's current one. A customer who can
show the rules changed between booking and forfeiture has a legitimate
dispute, not a misunderstanding — so it is tested directly rather than
inferred from the field existing.
"""

from datetime import timedelta

from django.contrib.auth.models import User
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, MerchantMembership, Space
from reservations.availability import is_space_available
from reservations.management.commands.lapse_no_shows import lapsed_reservations
from reservations.models import Reservation
from reservations.no_show import no_show_window


class LifecycleTestBase(APITestCase):
    def setUp(self):
        self.restaurant = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Kaloum',
        )
        self.lounge = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.restaurant_table = Space.objects.create(
            establishment=self.restaurant, name='Table 1', capacity=4
        )
        self.lounge_table = Space.objects.create(
            establishment=self.lounge, name='Salon 1', capacity=6
        )

        self.owner = User.objects.create_user('amadou', password='pw-for-tests')
        for venue in (self.restaurant, self.lounge):
            MerchantMembership.objects.create(
                user=self.owner,
                establishment=venue,
                role=MerchantMembership.Role.OWNER,
            )
        self.outsider = User.objects.create_user(
            'outsider', password='pw-for-tests'
        )

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def book(
        self,
        space=None,
        when=None,
        status_=Reservation.Status.CONFIRMED,
        **kwargs,
    ):
        return Reservation.objects.create(
            space=space or self.restaurant_table,
            customer_name='Mariama',
            customer_phone='+224620000000',
            datetime=when or (timezone.now() + timedelta(hours=2)),
            party_size=2,
            status=status_,
            **kwargs,
        )

    def complete_url(self, reservation):
        return reverse('reservation-complete', args=[reservation.pk])


class WindowCaptureTests(LifecycleTestBase):
    """D2: the default is per venue type, and captured when the booking is
    taken."""

    def test_a_restaurant_booking_takes_the_restaurant_window(self):
        reservation = self.book(space=self.restaurant_table)

        self.assertEqual(reservation.no_show_after_minutes, 30)

    def test_a_lounge_booking_takes_the_lounge_window(self):
        reservation = self.book(space=self.lounge_table)

        self.assertEqual(reservation.no_show_after_minutes, 90)

    def test_the_resolver_answers_per_type(self):
        self.assertEqual(no_show_window(self.restaurant), 30)
        self.assertEqual(no_show_window(self.lounge), 90)

    def test_a_booking_made_over_the_api_captures_it_too(self):
        """Not only direct creation — the path a customer actually uses."""
        response = self.client.post(
            reverse('reservation-list'),
            {
                'space': self.lounge_table.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'datetime': (timezone.now() + timedelta(days=1)).isoformat(),
                'party_size': 2,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['no_show_after_minutes'], 90)

    def test_the_venue_advertises_the_window_before_anyone_books(self):
        """A forfeiture is only defensible if this was on screen first."""
        response = self.client.get(
            reverse('establishment-detail', args=[self.restaurant.pk])
        )

        self.assertEqual(response.data['no_show_window_minutes'], 30)

    def test_changing_the_setting_only_affects_new_bookings(self):
        """**The property that keeps a forfeiture defensible.**

        A booking taken under a ninety-minute grace period keeps it. If the
        venue shortens its window on Tuesday, Monday's customer is still
        judged on what they were told — anything else is taking someone's
        money under rules they never agreed to.

        The override is a context manager rather than a decorator on purpose:
        as a decorator it would wrap the whole method, the "before" booking
        would be made under the new rules too, and the test would be checking
        nothing at all.
        """
        taken_before = self.book(space=self.lounge_table)
        self.assertEqual(taken_before.no_show_after_minutes, 90)

        with override_settings(
            NO_SHOW_WINDOW_MINUTES={'restaurant': 15, 'lounge': 45}
        ):
            taken_after = self.book(
                space=self.lounge_table,
                when=timezone.now() + timedelta(hours=6),
            )

            self.assertEqual(taken_after.no_show_after_minutes, 45)
            # Re-read from the database, not the in-memory instance, so this
            # cannot pass on a stale attribute.
            taken_before.refresh_from_db()
            self.assertEqual(taken_before.no_show_after_minutes, 90)

    def test_the_deadline_follows_the_captured_window(self):
        when = timezone.now() - timedelta(hours=5)
        reservation = self.book(space=self.lounge_table, when=when)

        self.assertEqual(
            reservation.no_show_deadline, when + timedelta(minutes=90)
        )


class CompleteActionTests(LifecycleTestBase):
    def test_an_owner_can_mark_guests_arrived(self):
        reservation = self.book(when=timezone.now() - timedelta(minutes=10))
        self.authenticate(self.owner)

        response = self.client.post(self.complete_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.COMPLETED)
        self.assertIsNotNone(reservation.arrived_at)

    def test_a_pending_booking_can_be_completed(self):
        """They turned up; whether the merchant got round to confirming is
        not the customer's problem."""
        reservation = self.book(
            when=timezone.now() - timedelta(minutes=10),
            status_=Reservation.Status.PENDING,
        )
        self.authenticate(self.owner)

        response = self.client.post(self.complete_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_a_booking_in_the_future_cannot_be_completed(self):
        """Otherwise a table is freed by marking tomorrow's guests as gone."""
        reservation = self.book(when=timezone.now() + timedelta(hours=3))
        self.authenticate(self.owner)

        response = self.client.post(self.complete_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.CONFIRMED)

    def test_a_cancelled_booking_cannot_be_completed(self):
        reservation = self.book(
            when=timezone.now() - timedelta(minutes=10),
            status_=Reservation.Status.CANCELLED,
        )
        self.authenticate(self.owner)

        response = self.client.post(self.complete_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_completing_twice_is_refused_rather_than_silently_repeated(self):
        reservation = self.book(when=timezone.now() - timedelta(minutes=10))
        self.authenticate(self.owner)
        self.client.post(self.complete_url(reservation))

        response = self.client.post(self.complete_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_a_non_member_cannot_complete(self):
        reservation = self.book(when=timezone.now() - timedelta(minutes=10))
        self.authenticate(self.outsider)

        response = self.client.post(self.complete_url(reservation))

        self.assertIn(
            response.status_code,
            {status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND},
        )
        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.CONFIRMED)

    def test_a_signed_out_caller_cannot_complete(self):
        reservation = self.book(when=timezone.now() - timedelta(minutes=10))

        response = self.client.post(self.complete_url(reservation))

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class LapseTests(LifecycleTestBase):
    def test_a_restaurant_booking_lapses_after_its_thirty_minutes(self):
        self.book(
            space=self.restaurant_table,
            when=timezone.now() - timedelta(minutes=31),
        )

        self.assertEqual(len(lapsed_reservations()), 1)

    def test_the_same_delay_does_not_lapse_a_lounge_booking(self):
        """The whole point of a per-type window, in one pair of tests."""
        self.book(
            space=self.lounge_table,
            when=timezone.now() - timedelta(minutes=31),
        )

        self.assertEqual(lapsed_reservations(), [])

    def test_a_lounge_booking_lapses_after_its_ninety(self):
        self.book(
            space=self.lounge_table,
            when=timezone.now() - timedelta(minutes=91),
        )

        self.assertEqual(len(lapsed_reservations()), 1)

    def test_a_booking_exactly_on_its_deadline_has_not_lapsed_yet(self):
        """The boundary belongs to the customer, not the venue."""
        when = timezone.now() - timedelta(minutes=30)
        self.book(space=self.restaurant_table, when=when)

        self.assertEqual(lapsed_reservations(now=when + timedelta(minutes=30)), [])

    def test_a_booking_someone_arrived_for_never_lapses(self):
        self.book(
            when=timezone.now() - timedelta(hours=4),
            status_=Reservation.Status.COMPLETED,
            arrived_at=timezone.now() - timedelta(hours=3),
        )

        self.assertEqual(lapsed_reservations(), [])

    def test_a_cancelled_booking_never_lapses(self):
        self.book(
            when=timezone.now() - timedelta(hours=4),
            status_=Reservation.Status.CANCELLED,
        )

        self.assertEqual(lapsed_reservations(), [])

    def test_a_booking_with_no_captured_window_is_left_alone(self):
        """Rows written before the field existed are not judged by today's
        rules."""
        reservation = self.book(when=timezone.now() - timedelta(hours=4))
        Reservation.objects.filter(pk=reservation.pk).update(
            no_show_after_minutes=None
        )

        self.assertEqual(lapsed_reservations(), [])

    def test_the_command_marks_them_missed(self):
        reservation = self.book(when=timezone.now() - timedelta(minutes=31))

        from django.core.management import call_command

        call_command('lapse_no_shows', verbosity=0)

        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.NO_SHOW)

    def test_running_the_command_twice_changes_nothing_the_second_time(self):
        """A scheduler will run this constantly."""
        from django.core.management import call_command

        reservation = self.book(when=timezone.now() - timedelta(minutes=31))
        call_command('lapse_no_shows', verbosity=0)
        reservation.refresh_from_db()
        first = reservation.status

        call_command('lapse_no_shows', verbosity=0)

        reservation.refresh_from_db()
        self.assertEqual(first, Reservation.Status.NO_SHOW)
        self.assertEqual(reservation.status, Reservation.Status.NO_SHOW)
        self.assertEqual(lapsed_reservations(), [])

    def test_a_dry_run_writes_nothing(self):
        from django.core.management import call_command

        reservation = self.book(when=timezone.now() - timedelta(minutes=31))
        call_command('lapse_no_shows', '--dry-run', verbosity=0)

        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.CONFIRMED)

    @override_settings(NO_SHOW_WINDOW_MINUTES={'restaurant': 5, 'lounge': 5})
    def test_shortening_the_window_does_not_lapse_an_existing_booking(self):
        """**The dispute this whole design exists to prevent.**

        Booked when the lounge held tables for ninety minutes, judged forty
        minutes later after the venue moved to five. The booking keeps its own
        window, so it has not lapsed.
        """
        self.book(
            space=self.lounge_table,
            when=timezone.now() - timedelta(minutes=40),
            no_show_after_minutes=90,
        )

        self.assertEqual(lapsed_reservations(), [])


class LapsedSlotTests(LifecycleTestBase):
    def test_a_missed_booking_releases_its_slot(self):
        when = timezone.now() - timedelta(minutes=31)
        reservation = self.book(space=self.restaurant_table, when=when)
        self.assertFalse(is_space_available(self.restaurant_table, when))

        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])

        self.assertTrue(is_space_available(self.restaurant_table, when))

    def test_a_completed_booking_keeps_holding_its_slot(self):
        """The sitting happened; the table was not free during it."""
        when = timezone.now() - timedelta(hours=3)
        reservation = self.book(when=when)
        reservation.status = Reservation.Status.COMPLETED
        reservation.save(update_fields=['status'])

        self.assertFalse(is_space_available(self.restaurant_table, when))

    def test_a_missed_slot_can_be_booked_by_somebody_else(self):
        when = timezone.now() + timedelta(minutes=1)
        first = self.book(space=self.restaurant_table, when=when)
        first.status = Reservation.Status.NO_SHOW
        first.save(update_fields=['status'])

        response = self.client.post(
            reverse('reservation-list'),
            {
                'space': self.restaurant_table.pk,
                'customer_name': 'Ibrahima',
                'customer_phone': '+224620000001',
                'datetime': when.isoformat(),
                'party_size': 2,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)


class MissedStatusTests(LifecycleTestBase):
    def test_the_customer_can_read_that_they_missed_it(self):
        reservation = self.book(when=timezone.now() - timedelta(hours=2))
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])

        response = self.client.get(
            reverse('reservation-by-reference', args=[reservation.reference])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'no_show')

    def test_missed_reads_as_missed_in_english(self):
        self.assertEqual(
            str(Reservation.Status.NO_SHOW.label), 'Missed'
        )

    def test_a_missed_booking_cannot_be_cancelled_by_the_customer(self):
        reservation = self.book(when=timezone.now() - timedelta(hours=2))
        reservation.status = Reservation.Status.NO_SHOW
        reservation.save(update_fields=['status'])

        response = self.client.post(
            reverse(
                'reservation-cancel-by-reference', args=[reservation.reference]
            )
        )

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
