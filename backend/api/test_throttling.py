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

from django.conf import settings
from django.contrib.auth.models import User
from django.core.cache import cache
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space

from .throttling import hits_since

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
            for i in range(1, 24)
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

    def test_the_number_may_be_booked_at_exactly_three_times(self):
        """**The boundary, named.**

        Tightened from five in Slice 28. A real customer books one number
        once, occasionally twice; three is honest peak plus one. Every unit
        above it is how often a stranger can make somebody's phone ring once
        a real gateway is attached, so this is asserted exactly rather than
        as "throttles eventually".
        """
        url = reverse('reservation-list')

        for i, table in enumerate(self.tables[:3]):
            response = self.client.post(
                url, self.booking_payload(table, hours=i + 1), format='json'
            )
            self.assertEqual(
                response.status_code,
                status.HTTP_201_CREATED,
                f'booking {i + 1} of 3 should be allowed',
            )

        refused = self.client.post(
            url, self.booking_payload(self.tables[3], hours=9), format='json'
        )
        self.assertEqual(refused.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    def test_one_connection_may_book_exactly_fifteen_times(self):
        """The per-IP ceiling, tightened from thirty.

        A different number each time, so this measures the connection rather
        than the phone — the two limits guard different abuses and must not
        be tested through each other.
        """
        url = reverse('reservation-list')

        for i, table in enumerate(self.tables[:15]):
            response = self.client.post(
                url,
                self.booking_payload(
                    table, phone=f'+22462000{i:04d}', hours=i + 1
                ),
                format='json',
            )
            self.assertEqual(
                response.status_code,
                status.HTTP_201_CREATED,
                f'booking {i + 1} of 15 should be allowed',
            )

        refused = self.client.post(
            url,
            self.booking_payload(
                self.tables[15], phone='+224629999999', hours=20
            ),
            format='json',
        )
        self.assertEqual(refused.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

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


@THROTTLED
class SurfaceThrottleTests(ThrottleTestBase):
    """The floor under the endpoints that name no throttle of their own.

    Measured rather than guessed in Slice 28, and the measurement moved the
    number the wrong way round: painting one browse list costs 22 requests
    because the list carries no cover and the app fetches one per venue, so
    the old 90/min ran out at four customers on one café connection.
    """

    def setUp(self):
        super().setUp()
        self.venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )

    def test_the_surface_allows_a_cafe_full_of_customers(self):
        url = reverse('establishment-photos', args=[self.venue.pk])

        codes = [self.client.get(url).status_code for _ in range(180)]

        self.assertNotIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)
        self.assertEqual(
            self.client.get(url).status_code,
            status.HTTP_429_TOO_MANY_REQUESTS,
            'the 181st request in a minute is the boundary',
        )

    def test_eight_browse_sessions_a_minute_still_fit(self):
        """The number that decides the rate, stated as what it buys.

        22 requests paints one list. Eight of those is a busy shared
        connection, and it must not look like an attack.
        """
        url = reverse('establishment-photos', args=[self.venue.pk])

        codes = [self.client.get(url).status_code for _ in range(8 * 22)]

        self.assertNotIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)


@THROTTLED
class ThrottleHitCountingTests(ThrottleTestBase):
    """A rate nobody can see being hit is a rate nobody can defend changing.

    Slice 20's metrics module claimed to answer "are the ceilings being hit?"
    and did not — there was no counter behind the sentence. Slice 28 needed
    one before it could size anything, so these guard the instrument rather
    than the limit.
    """

    def setUp(self):
        super().setUp()
        User.objects.create_user('amadou', password='correct-horse')
        self.admin = User.objects.create_superuser(
            'admin', password='correct-horse'
        )

    def test_a_refusal_is_counted_against_its_scope(self):
        self.post_repeatedly(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'wrong'},
            8,
        )

        self.assertGreater(hits_since('login_username', _an_hour_ago()), 0)

    def test_what_was_allowed_is_not_counted(self):
        """Only refusals. Counting every request would make the number
        useless for the one question it exists to answer."""
        self.client.post(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'correct-horse'},
            format='json',
        )

        self.assertEqual(hits_since('login_username', _an_hour_ago()), 0)

    def test_scopes_are_counted_apart(self):
        self.post_repeatedly(
            reverse('customer-register'),
            {'username': 'someone', 'password': 'chicha-2026'},
            8,
        )

        self.assertGreater(hits_since('register', _an_hour_ago()), 0)
        self.assertEqual(hits_since('booking_phone', _an_hour_ago()), 0)

    def test_the_metrics_endpoint_reports_every_scope(self):
        """Including the quiet ones.

        A scope missing from the payload reads as "never hit", and "never
        hit" must not look like "not being counted".
        """
        self.post_repeatedly(
            reverse('auth-login'),
            {'username': 'amadou', 'password': 'wrong'},
            8,
        )
        self.client.force_authenticate(self.admin)

        hits = self.client.get(reverse('metrics')).data['throttle_hits']

        self.assertGreater(hits['login_username'], 0)
        self.assertEqual(hits['booking_phone'], 0)
        self.assertEqual(
            set(hits),
            set(settings.REST_FRAMEWORK['DEFAULT_THROTTLE_RATES']),
        )


def _an_hour_ago():
    return timezone.now() - timedelta(hours=1)
