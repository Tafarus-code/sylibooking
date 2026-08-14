from datetime import datetime, time, timedelta

from django.contrib.auth.models import User
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space
from reservations.models import Reservation


class MerchantAuthTestBase(APITestCase):
    def setUp(self):
        self.baobab = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )
        self.fatou = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre-ville, Labé',
        )

        self.baobab_staff = User.objects.create_user('amadou', password='pw-for-tests')
        self.fatou_staff = User.objects.create_user('fatou', password='pw-for-tests')
        self.baobab.staff.add(self.baobab_staff)
        self.fatou.staff.add(self.fatou_staff)

        self.baobab_table = Space.objects.create(
            establishment=self.baobab, name='Table 4', capacity=4
        )
        self.fatou_table = Space.objects.create(
            establishment=self.fatou, name='Table 1', capacity=2
        )

        day = (timezone.localtime() + timedelta(days=1)).date()
        slot = timezone.make_aware(datetime.combine(day, time(hour=19)))

        self.baobab_booking = Reservation.objects.create(
            space=self.baobab_table,
            customer_name='Mariama Diallo',
            customer_phone='+224 620 00 00 00',
            datetime=slot,
            party_size=2,
        )
        self.fatou_booking = Reservation.objects.create(
            space=self.fatou_table,
            customer_name='Ibrahima Bah',
            customer_phone='+224 621 11 11 11',
            datetime=slot,
            party_size=2,
        )


    def list_url(self, establishment):
        return f'{reverse("reservation-list")}?establishment={establishment.pk}'

    def list_for(self, establishment):
        """Listing names one venue now; it is no longer merged."""
        return self.client.get(self.list_url(establishment))


class LoginTests(MerchantAuthTestBase):
    def test_valid_credentials_return_a_token(self):
        response = self.client.post(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'pw-for-tests'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['token'])
        self.assertEqual(
            response.data['token'], Token.objects.get(user=self.baobab_staff).key
        )

    def test_login_returns_the_users_establishments(self):
        """The app needs to know which venue's calendar to open."""
        response = self.client.post(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'pw-for-tests'},
            format='json',
        )
        names = [e['name'] for e in response.data['user']['establishments']]
        self.assertEqual(names, ['Le Petit Baobab'])

    def test_wrong_password_is_rejected(self):
        response = self.client.post(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'wrong'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_unknown_user_is_rejected(self):
        response = self.client.post(
            reverse('auth-login'),
            {'username': 'nobody', 'password': 'pw-for-tests'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_token_authenticates_subsequent_requests(self):
        token = Token.objects.create(user=self.baobab_staff)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
        response = self.list_for(self.baobab)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_me_requires_a_token(self):
        response = self.client.get(reverse('auth-me'))
        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_me_identifies_the_caller(self):
        token = Token.objects.create(user=self.baobab_staff)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
        response = self.client.get(reverse('auth-me'))
        self.assertEqual(response.data['username'], 'amadou')

    def test_logout_invalidates_the_token(self):
        token = Token.objects.create(user=self.baobab_staff)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        response = self.client.post(reverse('auth-logout'))
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

        response = self.client.get(reverse('auth-me'))
        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )


class ReservationScopingTests(MerchantAuthTestBase):
    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def test_merchant_only_sees_their_own_reservations(self):
        self.authenticate(self.baobab_staff)
        response = self.list_for(self.baobab)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(
            response.data['results'][0]['customer_name'], 'Mariama Diallo'
        )

    def test_asking_for_another_venue_is_refused_not_merely_empty(self):
        """A direct API call for someone else's venue is turned away."""
        self.authenticate(self.fatou_staff)

        response = self.list_for(self.baobab)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_user_with_no_membership_is_refused(self):
        outsider = User.objects.create_user('outsider', password='pw-for-tests')
        self.authenticate(outsider)

        response = self.list_for(self.baobab)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_venue_must_be_named(self):
        self.authenticate(self.baobab_staff)

        response = self.client.get(reverse('reservation-list'))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('establishment', response.data)

    def test_a_superuser_may_list_any_single_venue(self):
        admin = User.objects.create_superuser('root', password='pw-for-tests')
        self.authenticate(admin)

        # One venue's bookings, not both venues merged.
        self.assertEqual(self.list_for(self.baobab).data['count'], 1)
        self.assertEqual(self.list_for(self.fatou).data['count'], 1)

    def test_merchant_cannot_confirm_another_venues_booking(self):
        self.authenticate(self.baobab_staff)
        response = self.client.post(
            reverse('reservation-confirm', args=[self.fatou_booking.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.fatou_booking.refresh_from_db()
        self.assertEqual(self.fatou_booking.status, Reservation.Status.PENDING)

    def test_merchant_cannot_cancel_another_venues_booking(self):
        self.authenticate(self.baobab_staff)
        response = self.client.post(
            reverse('reservation-cancel', args=[self.fatou_booking.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_merchant_can_confirm_their_own_booking(self):
        self.authenticate(self.baobab_staff)
        response = self.client.post(
            reverse('reservation-confirm', args=[self.baobab_booking.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.baobab_booking.refresh_from_db()
        self.assertEqual(self.baobab_booking.status, Reservation.Status.CONFIRMED)

    def test_date_range_filters_the_week(self):
        """The merchant app's week view asks for one range, not seven days."""
        self.authenticate(self.baobab_staff)
        today = timezone.localtime().date()

        response = self.client.get(
            reverse('reservation-list'),
            {
                'establishment': self.baobab.pk,
                'date_from': today.isoformat(),
                'date_to': (today + timedelta(days=6)).isoformat(),
            },
        )
        self.assertEqual(response.data['count'], 1)

        response = self.client.get(
            reverse('reservation-list'),
            {
                'establishment': self.baobab.pk,
                'date_from': (today + timedelta(days=3)).isoformat(),
                'date_to': (today + timedelta(days=6)).isoformat(),
            },
        )
        self.assertEqual(response.data['count'], 0)

    def test_malformed_date_range_is_rejected(self):
        self.authenticate(self.baobab_staff)
        # Params go in the dict, not the URL: the test client replaces a
        # path's query string when data is supplied.
        response = self.client.get(
            reverse('reservation-list'),
            {'establishment': self.baobab.pk, 'date_from': '01-08-2026'},
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('date_from', response.data)

    def test_lookup_by_id_is_closed_to_anonymous_callers(self):
        """Retrieve by id used to be public so customers could check a booking.

        Sequential ids made that a way to read anyone's name and phone number
        by counting upwards, so customers now go through their reference
        instead — see api/test_customer_cancel.py.
        """
        response = self.client.get(
            reverse('reservation-detail', args=[self.baobab_booking.pk])
        )
        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_the_reference_still_reaches_the_booking(self):
        response = self.client.get(
            reverse(
                'reservation-by-reference', args=[self.baobab_booking.reference]
            )
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
