"""Customers viewing and cancelling their own booking by reference."""

import uuid
from datetime import datetime, time, timedelta

from django.contrib.auth.models import User
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space
from reservations.availability import is_space_available
from reservations.models import Reservation


class ReferenceTestBase(APITestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )
        self.space = Space.objects.create(
            establishment=self.establishment, name='Table 4', capacity=4
        )
        tomorrow = (timezone.localtime() + timedelta(days=1)).date()
        self.slot = timezone.make_aware(datetime.combine(tomorrow, time(hour=19)))

        self.booking = Reservation.objects.create(
            space=self.space,
            customer_name='Mariama Diallo',
            customer_phone='+224 620 00 00 00',
            datetime=self.slot,
            party_size=2,
        )

    def ref_url(self, reservation=None):
        return reverse(
            'reservation-by-reference',
            args=[(reservation or self.booking).reference],
        )

    def cancel_url(self, reservation=None):
        return reverse(
            'reservation-cancel-by-reference',
            args=[(reservation or self.booking).reference],
        )


class ReferenceIssuingTests(ReferenceTestBase):
    def test_every_reservation_gets_a_reference(self):
        self.assertIsNotNone(self.booking.reference)

    def test_references_are_unique(self):
        other = Reservation.objects.create(
            space=self.space,
            customer_name='Ibrahima Bah',
            customer_phone='+224 621 11 11 11',
            datetime=self.slot + timedelta(hours=3),
            party_size=2,
        )
        self.assertNotEqual(self.booking.reference, other.reference)

    def test_booking_response_includes_the_reference(self):
        """The customer cannot come back later without it."""
        response = self.client.post(
            reverse('reservation-list'),
            {
                'space': self.space.pk,
                'customer_name': 'Aissatou Barry',
                'customer_phone': '+224 622 33 44 55',
                'datetime': (self.slot + timedelta(hours=5)).isoformat(),
                'party_size': 2,
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn('reference', response.data)
        self.assertTrue(response.data['reference'])

    def test_reference_cannot_be_set_by_the_client(self):
        forged = uuid.uuid4()
        response = self.client.post(
            reverse('reservation-list'),
            {
                'space': self.space.pk,
                'reference': str(forged),
                'customer_name': 'Aissatou Barry',
                'customer_phone': '+224 622 33 44 55',
                'datetime': (self.slot + timedelta(hours=5)).isoformat(),
                'party_size': 2,
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertNotEqual(response.data['reference'], str(forged))


class SequentialIdIsNoLongerAWayInTests(ReferenceTestBase):
    """The hole this feature closes: guessing #1, #2, #3 used to work."""

    def test_anonymous_cannot_read_a_booking_by_id(self):
        response = self.client.get(
            reverse('reservation-detail', args=[self.booking.pk])
        )
        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_unrelated_merchant_cannot_read_a_booking_by_id(self):
        outsider = User.objects.create_user('outsider', password='pw-for-tests')
        token = Token.objects.create(user=outsider)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        response = self.client.get(
            reverse('reservation-detail', args=[self.booking.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_the_venues_own_staff_can_still_read_it_by_id(self):
        staff = User.objects.create_user('amadou', password='pw-for-tests')
        self.establishment.staff.add(staff)
        token = Token.objects.create(user=staff)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        response = self.client.get(
            reverse('reservation-detail', args=[self.booking.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class ReadByReferenceTests(ReferenceTestBase):
    def test_the_reference_holder_can_read_it_without_signing_in(self):
        response = self.client.get(self.ref_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['customer_name'], 'Mariama Diallo')
        self.assertEqual(response.data['establishment_name'], 'Le Petit Baobab')

    def test_an_unknown_reference_is_a_404(self):
        url = reverse('reservation-by-reference', args=[uuid.uuid4()])
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_malformed_reference_does_not_reach_the_view(self):
        response = self.client.get('/api/reservations/ref/not-a-uuid/')
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_can_cancel_is_true_for_an_upcoming_booking(self):
        response = self.client.get(self.ref_url())
        self.assertTrue(response.data['can_cancel'])


class CancelByReferenceTests(ReferenceTestBase):
    def test_customer_can_cancel_their_own_booking(self):
        response = self.client.post(self.cancel_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Reservation.Status.CANCELLED)

    def test_cancelling_frees_the_slot(self):
        """The whole point: the table goes back on sale."""
        self.assertFalse(is_space_available(self.space, self.slot))

        self.client.post(self.cancel_url())

        self.assertTrue(is_space_available(self.space, self.slot))

    def test_cancelling_twice_is_a_no_op_not_an_error(self):
        """A customer on a flaky connection may well tap twice."""
        self.assertEqual(
            self.client.post(self.cancel_url()).status_code,
            status.HTTP_200_OK,
        )
        second = self.client.post(self.cancel_url())

        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertEqual(second.data['status'], Reservation.Status.CANCELLED)

    def test_a_confirmed_booking_can_still_be_cancelled(self):
        self.booking.status = Reservation.Status.CONFIRMED
        self.booking.save(update_fields=['status'])

        response = self.client.post(self.cancel_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Reservation.Status.CANCELLED)

    def test_a_completed_visit_cannot_be_cancelled(self):
        self.booking.status = Reservation.Status.COMPLETED
        self.booking.save(update_fields=['status'])

        response = self.client.post(self.cancel_url())

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('already happened', response.data['detail'])

    def test_a_booking_that_has_started_is_sent_to_the_venue(self):
        """Cancelling a visit already under way would rewrite history."""
        self.booking.datetime = timezone.now() - timedelta(minutes=30)
        self.booking.save(update_fields=['datetime'])

        response = self.client.post(self.cancel_url())

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('call the venue', response.data['detail'].lower())
        self.booking.refresh_from_db()
        self.assertEqual(self.booking.status, Reservation.Status.PENDING)

    def test_can_cancel_is_false_once_the_booking_has_started(self):
        self.booking.datetime = timezone.now() - timedelta(minutes=30)
        self.booking.save(update_fields=['datetime'])

        response = self.client.get(self.ref_url())

        self.assertFalse(response.data['can_cancel'])

    def test_cancelling_an_unknown_reference_is_a_404(self):
        url = reverse('reservation-cancel-by-reference', args=[uuid.uuid4()])
        response = self.client.post(url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_one_customers_reference_does_not_cancel_anothers_booking(self):
        other = Reservation.objects.create(
            space=self.space,
            customer_name='Ibrahima Bah',
            customer_phone='+224 621 11 11 11',
            datetime=self.slot + timedelta(hours=4),
            party_size=2,
        )

        self.client.post(self.cancel_url(other))

        other.refresh_from_db()
        self.booking.refresh_from_db()
        self.assertEqual(other.status, Reservation.Status.CANCELLED)
        self.assertEqual(self.booking.status, Reservation.Status.PENDING)
