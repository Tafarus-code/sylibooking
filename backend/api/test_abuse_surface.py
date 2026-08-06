"""The sweep after the exposed paths were already closed.

Slice 10 put ceilings on the endpoints that would turn into a harassment
vector the moment a payment gateway is attached. What is left here is
nuisance and cost rather than exposure: a route added next month with nobody
remembering to cover it, a competitor pulling the catalogue nightly, a
gallery filled with four hundred admissible photos, and a reset endpoint that
answers "maybe" in a measurably different length of time depending on whether
the answer is really yes.

Throttling is off for the rest of the suite, so these turn it back on and
clear the cache between them.
"""

import copy
import time as clock
from datetime import timedelta

from accounts.models import CustomerProfile
from django.conf import settings
from django.contrib.auth.models import User
from django.core.cache import cache
from django.db import IntegrityError, transaction
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.favourites import Favourite
from establishments.models import (
    Establishment,
    MerchantMembership,
    Photo,
    Review,
    Space,
)
from reservations.models import Reservation

from .test_reviews_and_photos import MediaRootMixin, make_image


def rates(**overrides):
    """Throttling on, with some rates dialled down to something testable.

    Built from the real settings rather than replacing them, so a test that
    tightens one ceiling still exercises the others as configured.
    """
    conf = copy.deepcopy(settings.REST_FRAMEWORK)
    conf['DEFAULT_THROTTLE_RATES'] = {
        **conf['DEFAULT_THROTTLE_RATES'],
        **overrides,
    }
    return override_settings(REST_FRAMEWORK=conf, THROTTLING_ENABLED=True)


class SurfaceTestBase(APITestCase):
    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)

        self.venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )

    def codes(self, url, times, **params):
        return [
            self.client.get(url, params).status_code for _ in range(times)
        ]


class DefaultCoverageTests(SurfaceTestBase):
    """The floor under everything nobody thought to cover."""

    @rates(anon_surface='3/min')
    def test_an_endpoint_that_names_no_throttle_is_still_covered(self):
        # Theme presets asks for nothing and protects nothing; the point is
        # that it did not have to opt in.
        codes = self.codes(reverse('theme-presets'), 5)

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    @rates(anon_surface='1000/min')
    def test_a_loose_default_does_not_loosen_the_login_limit(self):
        """**The one the slice exists to not get wrong.**

        A blanket ceiling set generously must not become the ceiling on the
        paths that earned a tighter one.
        """
        User.objects.create_user('amadou', password='correct-horse')

        codes = [
            self.client.post(
                reverse('auth-login'),
                {'username': 'amadou', 'password': 'wrong'},
                format='json',
            ).status_code
            for _ in range(8)
        ]

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    @rates(anon_surface='1/min')
    def test_and_a_tight_default_does_not_tighten_it_either(self):
        """Naming throttles on a view replaces the defaults there.

        Worth pinning rather than assuming: it is DRF's behaviour, not ours,
        and if it ever changed the login limit would silently become whatever
        the blanket rate happens to be.
        """
        User.objects.create_user('amadou', password='correct-horse')

        codes = [
            self.client.post(
                reverse('auth-login'),
                {'username': 'amadou', 'password': 'correct-horse'},
                format='json',
            ).status_code
            for _ in range(3)
        ]

        self.assertNotIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    @rates(anon_surface='1/min', user_surface='60/min')
    def test_signing_in_buys_the_higher_ceiling(self):
        """A merchant tablet polling all evening is the app working."""
        owner = User.objects.create_user('amadou', password='pw-for-tests')
        MerchantMembership.objects.create(
            user=owner,
            establishment=self.venue,
            role=MerchantMembership.Role.OWNER,
        )
        token, _ = Token.objects.get_or_create(user=owner)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        codes = self.codes(reverse('merchant-establishments'), 5)

        self.assertNotIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)


class BrowseTests(SurfaceTestBase):
    """The catalogue is public. Public and unlimited are different."""

    @rates(browse='3/hour')
    def test_pulling_the_whole_list_is_capped(self):
        codes = self.codes(reverse('establishment-list'), 5)

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    @rates(browse='3/hour')
    def test_detail_pages_count_against_the_same_ceiling(self):
        """Otherwise the cap is a speed bump: walk the ids instead."""
        self.client.get(reverse('establishment-list'))
        self.client.get(reverse('establishment-list'))

        codes = [
            self.client.get(
                reverse('establishment-detail', args=[self.venue.pk])
            ).status_code
            for _ in range(3)
        ]

        self.assertIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)

    @rates()
    def test_a_person_looking_around_never_meets_it(self):
        """Twenty requests is a customer comparing venues, not a scraper."""
        codes = self.codes(reverse('establishment-list'), 20)

        self.assertNotIn(status.HTTP_429_TOO_MANY_REQUESTS, codes)


class PhotoVolumeTests(MediaRootMixin, SurfaceTestBase):
    """A size cap bounds each file and nothing else."""

    def setUp(self):
        super().setUp()
        self.table = Space.objects.create(
            establishment=self.venue, name='Table 4', capacity=4
        )
        self.booking = Reservation.objects.create(
            space=self.table,
            customer_name='Mariama Diallo',
            customer_phone='+224620000000',
            datetime=timezone.now() - timedelta(days=1),
            party_size=2,
        )

    def post_photo(self, venue=None):
        return self.client.post(
            reverse('establishment-photos', args=[(venue or self.venue).pk]),
            {
                'reservation_reference': str(self.booking.reference),
                'image': make_image(),
            },
            format='multipart',
        )

    @override_settings(MAX_PHOTOS_PER_VENUE_PER_DAY=2)
    def test_a_gallery_stops_taking_photos_for_the_day(self):
        codes = [self.post_photo().status_code for _ in range(3)]

        self.assertEqual(codes[:2], [status.HTTP_201_CREATED] * 2)
        self.assertEqual(codes[2], status.HTTP_429_TOO_MANY_REQUESTS)

    @override_settings(MAX_PHOTOS_PER_VENUE_PER_DAY=1)
    def test_and_says_to_come_back_tomorrow(self):
        self.post_photo()

        response = self.post_photo()

        self.assertIn('tomorrow', response.data['detail'].lower())

    @override_settings(MAX_PHOTOS_PER_VENUE_PER_DAY=1)
    def test_yesterday_does_not_count_against_today(self):
        """A daily cap that never resets is a total cap wearing a disguise."""
        photo = Photo.objects.create(
            establishment=self.venue,
            reservation=self.booking,
            uploaded_by_role=Photo.UploaderRole.CUSTOMER,
        )
        # created_at is auto_now_add, so age it deliberately.
        Photo.objects.filter(pk=photo.pk).update(
            created_at=timezone.now() - timedelta(days=1)
        )

        response = self.post_photo()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    @override_settings(MAX_PHOTOS_PER_VENUE_PER_DAY=1)
    def test_one_busy_venue_does_not_silence_another(self):
        other = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Ratoma',
        )
        table = Space.objects.create(
            establishment=other, name='Table 1', capacity=2
        )
        theirs = Reservation.objects.create(
            space=table,
            customer_name='Ibrahima Bah',
            customer_phone='+224620999999',
            datetime=timezone.now() - timedelta(days=1),
            party_size=2,
        )
        self.post_photo()

        response = self.client.post(
            reverse('establishment-photos', args=[other.pk]),
            {
                'reservation_reference': str(theirs.reference),
                'image': make_image(),
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)


class ResetTimingTests(APITestCase):
    """A yes and a no should not be distinguishable by stopwatch."""

    FLOOR = 0.2

    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)
        user = User.objects.create_user('mariama', password='chicha-2026')
        CustomerProfile.objects.create(user=user, phone='+224620000000')

    def ask(self, identifier):
        started = clock.monotonic()
        response = self.client.post(
            reverse('customer-password-reset'),
            {'identifier': identifier},
            format='json',
        )
        return response, clock.monotonic() - started

    @override_settings(PASSWORD_RESET_MIN_SECONDS=FLOOR)
    def test_an_account_that_exists_is_not_answered_faster(self):
        _, elapsed = self.ask('mariama')

        self.assertGreaterEqual(elapsed, self.FLOOR)

    @override_settings(PASSWORD_RESET_MIN_SECONDS=FLOOR)
    def test_and_neither_is_one_that_does_not(self):
        """The half that used to return after a single query."""
        _, elapsed = self.ask('nobody-at-all')

        self.assertGreaterEqual(elapsed, self.FLOOR)

    @override_settings(PASSWORD_RESET_MIN_SECONDS=FLOOR)
    def test_both_answers_read_the_same(self):
        hit, _ = self.ask('mariama')
        miss, _ = self.ask('nobody-at-all')

        self.assertEqual(hit.status_code, miss.status_code)
        self.assertEqual(hit.data['detail'], miss.data['detail'])

    @override_settings(PASSWORD_RESET_MIN_SECONDS=FLOOR)
    def test_but_the_success_still_names_where_it_went(self):
        """**Documented, not defended.**

        A hit carries a masked destination so the right person knows which
        phone to look at; a miss cannot carry one. So the bodies differ in
        length and a caller can still tell an account exists — the timing
        floor closes the stopwatch, not this.

        Pinned here so the trade-off is visible and deliberate rather than
        discovered. Removing `sent_to` would close it and would leave a
        customer with two numbers no idea which one to check.
        """
        hit, _ = self.ask('mariama')
        miss, _ = self.ask('nobody-at-all')

        self.assertIn('sent_to', hit.data)
        self.assertNotIn('sent_to', miss.data)


class SpamShapeTests(SurfaceTestBase):
    """Review and favourite spam, confirmed rather than assumed.

    Both are already blunted by shape rather than by rate: a review is tied
    one-to-one to a booking, a favourite is unique per person and venue. The
    endpoints are tested elsewhere; these check the constraint is in the
    database, where a new code path cannot get around it.
    """

    def test_a_booking_carries_at_most_one_review(self):
        table = Space.objects.create(
            establishment=self.venue, name='Table 4', capacity=4
        )
        booking = Reservation.objects.create(
            space=table,
            customer_name='Mariama Diallo',
            customer_phone='+224620000000',
            datetime=timezone.now() - timedelta(days=1),
            party_size=2,
        )
        Review.objects.create(
            establishment=self.venue, reservation=booking, rating=5
        )

        with self.assertRaises(IntegrityError), transaction.atomic():
            Review.objects.create(
                establishment=self.venue, reservation=booking, rating=1
            )

    def test_a_venue_can_be_favourited_once_per_person(self):
        user = User.objects.create_user('mariama', password='chicha-2026')
        Favourite.objects.create(user=user, establishment=self.venue)

        with self.assertRaises(IntegrityError), transaction.atomic():
            Favourite.objects.create(user=user, establishment=self.venue)
