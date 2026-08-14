"""Ceilings on the endpoints anyone can reach without signing in.

Today the worst an abuser gets from hammering these is junk rows. The moment
a real payment gateway is attached, booking-create becomes a way to push a
mobile money prompt at any number in Guinea, as often as they like, from our
provider account. That is why this lands before the gateway rather than after,
and it is what these tests are really protecting.

Throttling is off for the rest of the suite — a counter that outlives a test
would have every test that signs in twice fighting it — so these turn it back
on explicitly and clear the cache between them.
"""

from datetime import timedelta

from django.contrib.auth.models import User
from django.core.cache import cache
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space

THROTTLED = override_settings(THROTTLING_ENABLED=True)


class ThrottleTestBase(APITestCase):
    def setUp(self):
        # Throttle history lives in the cache and outlives a test otherwise.
        cache.clear()
        self.addCleanup(cache.clear)

    def post_repeatedly(self, url, payload, times):
        """Returns the status codes, in order."""
        return [
            self.client.post(url, payload, format='json').status_code
            for _ in range(times)
        ]


@THROTTLED
class LoginThrottleTests(ThrottleTestBase):
    def setUp(self):
        super().setUp()
        User.objects.create_user('amadou', password='correct-horse')

    def test_guessing_one_account_is_cut_off(self):
        codes = self.post_repeatedly(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'wrong'},
            8,
        )

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    def test_the_refusal_says_when_to_come_back(self):
        url = reverse('auth-login')
        payload = {'username': 'amadou', 'password': 'wrong'}
        for _ in range(8):
            response = self.client.post(url, payload, format='json')
            if response.status_code == status.HTTP_429_TOO_MANY_REQUESTS:
                break

        self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
        # A 429 with no Retry-After tells a client to guess.
        self.assertIn('Retry-After', response.headers)

    def test_a_second_account_from_the_same_place_is_not_locked_out(self):
        """Per username as well as per IP.

        A staff room behind one connection must not lock each other out just
        because one of them fat-fingered their password.
        """
        User.objects.create_user('ibrahima', password='also-correct')
        url = reverse('auth-login')

        for _ in range(5):
            self.client.post(
                url, {'username': 'amadou', 'password': 'wrong'}, format='json'
            )
        response = self.client.post(
            url,
            {'username': 'ibrahima', 'password': 'also-correct'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_a_correct_password_still_works_below_the_limit(self):
        response = self.client.post(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'correct-horse'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)


@THROTTLED
class PasswordResetThrottleTests(ThrottleTestBase):
    """**The hole this slice exists to close.**

    The five-attempt cap on a reset code is per code. Nothing capped how many
    codes could be asked for, so unthrottled it was unlimited attempts wearing
    a fresh code each time.
    """

    def setUp(self):
        super().setUp()
        User.objects.create_user('mariama', password='x' * 10)

    def test_asking_for_code_after_code_is_cut_off(self):
        codes = self.post_repeatedly(
            reverse('customer-password-reset'),
            {'identifier': 'mariama'},
            6,
        )

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    def test_the_cap_follows_the_account_not_only_the_connection(self):
        """Otherwise rotating IPs buys unlimited codes for one victim."""
        url = reverse('customer-password-reset')
        for _ in range(3):
            self.client.post(url, {'identifier': 'mariama'}, format='json')

        # A different address from the same place is a different target.
        response = self.client.post(
            url, {'identifier': 'someone-else'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_confirming_is_capped_too(self):
        codes = self.post_repeatedly(
            reverse('customer-password-reset-confirm'),
            {'identifier': 'mariama', 'code': '000000', 'password': 'y' * 10},
            8,
        )

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)


@THROTTLED
class RegistrationThrottleTests(ThrottleTestBase):
    def test_making_account_after_account_is_cut_off(self):
        url = reverse('customer-register')
        codes = [
            self.client.post(
                url,
                {'username': f'person{i}', 'password': 'chicha-2026'},
                format='json',
            ).status_code
            for i in range(8)
        ]

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)


@THROTTLED
class BookingThrottleTests(ThrottleTestBase):
    def setUp(self):
        super().setUp()
        self.venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.tables = [
            Space.objects.create(
                establishment=self.venue, name=f'Table {i}', capacity=4
            )
            for i in range(1, 12)
        ]

    def booking_payload(self, table, phone='+224620000000', hours=1):
        return {
            'space': table.pk,
            'customer_name': 'Mariama',
            'customer_phone': phone,
            'datetime': (
                timezone.now() + timedelta(hours=hours)
            ).isoformat(),
            'party_size': 2,
        }

    def test_one_number_cannot_be_booked_at_over_and_over(self):
        """**The prompt-spam ceiling.**

        Once a booking can initiate a real payment, this is what stops one
        phone number being made to ring all afternoon.
        """
        url = reverse('reservation-list')
        codes = []
        for i, table in enumerate(self.tables[:8]):
            response = self.client.post(
                url, self.booking_payload(table, hours=i + 1), format='json'
            )
            codes.append(response.status_code)

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    def test_a_different_number_is_not_affected(self):
        """An abuser has to pick a victim; other customers keep booking."""
        url = reverse('reservation-list')
        for i, table in enumerate(self.tables[:5]):
            self.client.post(
                url, self.booking_payload(table, hours=i + 1), format='json'
            )

        response = self.client.post(
            url,
            self.booking_payload(
                self.tables[9], phone='+224620009999', hours=9
            ),
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_reading_a_booking_is_never_throttled(self):
        """Only creating is. Browsing is not the path an abuser uses."""
        url = reverse('reservation-list')
        created = self.client.post(
            url, self.booking_payload(self.tables[0]), format='json'
        )
        reference = created.data['reference']

        codes = [
            self.client.get(
                reverse('reservation-by-reference', args=[reference])
            ).status_code
            for _ in range(30)
        ]

        self.assertNotIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    def test_browsing_venues_is_never_throttled(self):
        codes = [
            self.client.get(reverse('establishment-list')).status_code
            for _ in range(40)
        ]

        self.assertNotIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)


class SwitchTests(ThrottleTestBase):
    """The suite runs with throttling off; that has to actually be true."""

    def test_the_rest_of_the_suite_is_not_throttled(self):
        User.objects.create_user('amadou', password='correct-horse')
        url = reverse('auth-login')

        codes = [
            self.client.post(
                url,
                {'username': 'amadou', 'password': 'correct-horse'},
                format='json',
            ).status_code
            for _ in range(20)
        ]

        self.assertNotIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    @THROTTLED
    def test_and_can_be_switched_on(self):
        User.objects.create_user('amadou', password='correct-horse')

        codes = self.post_repeatedly(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'wrong'},
            8,
        )

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)
