from datetime import datetime, time, timedelta

from django.contrib.auth.models import User
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import status
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space
from reservations.models import Reservation


class APITestBase(APITestCase):
    def setUp(self):
        self.lounge = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )
        self.restaurant = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre-ville, Labé',
        )
        self.table = Space.objects.create(
            establishment=self.lounge,
            name='Table 4',
            type=Space.Type.TABLE,
            capacity=4,
        )
        self.vip = Space.objects.create(
            establishment=self.lounge,
            name='VIP Room 1',
            type=Space.Type.VIP_ROOM,
            capacity=10,
        )

        # Tomorrow at 19:00 local: inside the availability window, never past.
        self.day = (timezone.localtime() + timedelta(days=1)).date()
        self.slot = timezone.make_aware(datetime.combine(self.day, time(hour=19)))

    def book(self, space=None, when=None, **overrides):
        fields = {
            'space': space or self.table,
            'customer_name': 'Mariama Diallo',
            'customer_phone': '+224 620 00 00 00',
            'datetime': when or self.slot,
            'party_size': 2,
        }
        fields.update(overrides)
        return Reservation.objects.create(**fields)


class EstablishmentEndpointTests(APITestBase):
    def test_list_is_public(self):
        response = self.client.get(reverse('establishment-list'))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 2)

    def test_list_includes_space_count(self):
        response = self.client.get(reverse('establishment-list'))
        by_name = {row['name']: row for row in response.data['results']}
        self.assertEqual(by_name['Le Petit Baobab']['space_count'], 2)
        self.assertEqual(by_name['Chez Fatou']['space_count'], 0)

    def test_filter_by_city_is_case_insensitive(self):
        response = self.client.get(reverse('establishment-list'), {'city': 'conakry'})
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['name'], 'Le Petit Baobab')

    def test_filter_by_type(self):
        response = self.client.get(
            reverse('establishment-list'), {'type': 'restaurant'}
        )
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['name'], 'Chez Fatou')

    def test_detail_embeds_spaces(self):
        response = self.client.get(
            reverse('establishment-detail', args=[self.lounge.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            sorted(space['name'] for space in response.data['spaces']),
            ['Table 4', 'VIP Room 1'],
        )

    def test_is_read_only(self):
        response = self.client.post(reverse('establishment-list'), {'name': 'Nope'})
        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)


class AvailabilityEndpointTests(APITestBase):
    def url(self):
        return reverse('establishment-availability', args=[self.lounge.pk])

    def slots_by_space(self, response):
        return {row['space']['name']: row['slots'] for row in response.data['spaces']}

    def slot_at(self, slots, moment):
        for slot in slots:
            if parse_datetime(slot['start']) == moment:
                return slot
        raise AssertionError(f'no slot starting at {moment}')

    def test_requires_a_date(self):
        response = self.client.get(self.url())
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('date', response.data)

    def test_rejects_a_malformed_date(self):
        response = self.client.get(self.url(), {'date': '31-12-2026'})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('date', response.data)

    def test_every_slot_is_free_when_nothing_is_booked(self):
        response = self.client.get(self.url(), {'date': self.day.isoformat()})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['spaces']), 2)

        slots = self.slots_by_space(response)['Table 4']
        self.assertTrue(slots)
        self.assertTrue(all(slot['available'] for slot in slots))

    def test_booked_slot_is_marked_unavailable(self):
        self.book(space=self.table, when=self.slot)
        response = self.client.get(self.url(), {'date': self.day.isoformat()})
        by_space = self.slots_by_space(response)

        self.assertFalse(self.slot_at(by_space['Table 4'], self.slot)['available'])
        # The other space is untouched.
        self.assertTrue(all(slot['available'] for slot in by_space['VIP Room 1']))

    def test_slots_inside_the_hold_are_unavailable(self):
        """A 19:00 booking blocks 18:00 through 20:30 on a two-hour hold."""
        self.book(space=self.table, when=self.slot)
        response = self.client.get(self.url(), {'date': self.day.isoformat()})
        slots = self.slots_by_space(response)['Table 4']

        self.assertFalse(
            self.slot_at(slots, self.slot + timedelta(hours=1))['available']
        )
        self.assertFalse(
            self.slot_at(slots, self.slot - timedelta(hours=1))['available']
        )
        # Exactly two hours either side is clear again.
        self.assertTrue(
            self.slot_at(slots, self.slot + timedelta(hours=2))['available']
        )

    def test_cancelled_reservation_frees_the_slot(self):
        self.book(when=self.slot, status=Reservation.Status.CANCELLED)
        response = self.client.get(self.url(), {'date': self.day.isoformat()})
        slots = self.slots_by_space(response)['Table 4']
        self.assertTrue(all(slot['available'] for slot in slots))

    def test_party_size_filters_out_spaces_that_are_too_small(self):
        response = self.client.get(
            self.url(), {'date': self.day.isoformat(), 'party_size': 8}
        )
        names = [row['space']['name'] for row in response.data['spaces']]
        self.assertEqual(names, ['VIP Room 1'])

    def test_rejects_a_non_numeric_party_size(self):
        response = self.client.get(
            self.url(), {'date': self.day.isoformat(), 'party_size': 'four'}
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_establishment_with_no_spaces_returns_an_empty_list(self):
        response = self.client.get(
            reverse('establishment-availability', args=[self.restaurant.pk]),
            {'date': self.day.isoformat()},
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['spaces'], [])


class ReservationCreateTests(APITestBase):
    def payload(self, **overrides):
        data = {
            'space': self.table.pk,
            'customer_name': 'Mariama Diallo',
            'customer_phone': '+224 620 00 00 00',
            'datetime': self.slot.isoformat(),
            'party_size': 2,
        }
        data.update(overrides)
        return data

    def post(self, **overrides):
        return self.client.post(
            reverse('reservation-list'), self.payload(**overrides), format='json'
        )

    def test_anyone_can_book(self):
        response = self.post()
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Reservation.objects.count(), 1)

    def test_new_booking_is_pending(self):
        self.assertEqual(self.post().data['status'], Reservation.Status.PENDING)

    def test_client_cannot_self_confirm(self):
        """status is read-only: sending "confirmed" must not stick."""
        response = self.post(status=Reservation.Status.CONFIRMED)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Reservation.objects.get().status, Reservation.Status.PENDING)

    def test_double_booking_is_rejected(self):
        self.book(space=self.table, when=self.slot)
        response = self.post()
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('datetime', response.data)

    def test_overlapping_booking_is_rejected(self):
        """An hour later still falls inside the two-hour hold."""
        self.book(space=self.table, when=self.slot)
        response = self.post(datetime=(self.slot + timedelta(hours=1)).isoformat())
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_booking_after_the_hold_expires_is_allowed(self):
        self.book(space=self.table, when=self.slot)
        response = self.post(datetime=(self.slot + timedelta(hours=3)).isoformat())
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_same_time_on_a_different_space_is_allowed(self):
        self.book(space=self.table, when=self.slot)
        response = self.post(space=self.vip.pk)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_party_size_over_capacity_is_rejected(self):
        response = self.post(party_size=9)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('party_size', response.data)

    def test_booking_in_the_past_is_rejected(self):
        response = self.post(
            datetime=(timezone.now() - timedelta(days=1)).isoformat()
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('datetime', response.data)

    def test_cancelled_booking_does_not_block_the_slot(self):
        self.book(space=self.table, when=self.slot, status=Reservation.Status.CANCELLED)
        self.assertEqual(self.post().status_code, status.HTTP_201_CREATED)


class ReservationMerchantTests(APITestBase):
    def setUp(self):
        super().setUp()
        self.staff = User.objects.create_user('merchant', password='not-a-real-pw')
        # Reservations are scoped to the venues a user staffs; see
        # api/test_auth.py for the cross-establishment isolation tests.
        self.lounge.staff.add(self.staff)
        self.reservation = self.book()

    def list_reservations(self, **params):
        params.setdefault('establishment', self.lounge.pk)
        return self.client.get(reverse('reservation-list'), params)

    def test_listing_requires_authentication(self):
        """Customer names and phone numbers must not be public."""
        response = self.list_reservations()
        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_authenticated_merchant_can_list(self):
        self.client.force_authenticate(self.staff)
        response = self.list_reservations()
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)

    def test_list_can_be_filtered_by_date(self):
        self.client.force_authenticate(self.staff)
        response = self.list_reservations(date=self.day.isoformat())
        self.assertEqual(response.data['count'], 1)

        other_day = (self.day + timedelta(days=3)).isoformat()
        response = self.list_reservations(date=other_day)
        self.assertEqual(response.data['count'], 0)

    def test_a_venue_the_merchant_does_not_staff_is_refused(self):
        """Scoping is enforced, not merely filtered to nothing."""
        self.client.force_authenticate(self.staff)
        response = self.list_reservations(establishment=self.restaurant.pk)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_confirm_requires_authentication(self):
        response = self.client.post(
            reverse('reservation-confirm', args=[self.reservation.pk])
        )
        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_merchant_can_confirm(self):
        self.client.force_authenticate(self.staff)
        response = self.client.post(
            reverse('reservation-confirm', args=[self.reservation.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.status, Reservation.Status.CONFIRMED)

    def test_merchant_can_cancel(self):
        self.client.force_authenticate(self.staff)
        response = self.client.post(
            reverse('reservation-cancel', args=[self.reservation.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.status, Reservation.Status.CANCELLED)

    def test_cancelled_booking_cannot_be_confirmed(self):
        self.client.force_authenticate(self.staff)
        self.reservation.status = Reservation.Status.CANCELLED
        self.reservation.save(update_fields=['status'])

        response = self.client.post(
            reverse('reservation-confirm', args=[self.reservation.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_completed_booking_cannot_be_cancelled(self):
        self.client.force_authenticate(self.staff)
        self.reservation.status = Reservation.Status.COMPLETED
        self.reservation.save(update_fields=['status'])

        response = self.client.post(
            reverse('reservation-cancel', args=[self.reservation.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_cancelling_frees_the_slot_for_someone_else(self):
        """The end-to-end point of cancel: the table becomes bookable again."""
        self.client.force_authenticate(self.staff)
        self.client.post(reverse('reservation-cancel', args=[self.reservation.pk]))
        self.client.force_authenticate(None)

        response = self.client.post(
            reverse('reservation-list'),
            {
                'space': self.table.pk,
                'customer_name': 'Ibrahima Bah',
                'customer_phone': '+224 621 11 11 11',
                'datetime': self.slot.isoformat(),
                'party_size': 2,
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)


class SmokeTests(TestCase):
    def test_api_root_lists_both_collections(self):
        response = self.client.get('/api/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('establishments', response.data)
        self.assertIn('reservations', response.data)