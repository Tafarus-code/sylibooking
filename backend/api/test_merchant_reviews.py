"""A venue reading what its customers said about it.

Until now a merchant could not see their own reviews at all, and one who
cannot read them in the app reads them on Facebook instead — where nobody can
flag anything and the platform hears about a problem last.

The rule these are really guarding: **a merchant may flag and may not hide.**
Flagging asks an admin to look and changes nothing a customer sees. A venue
that could delete its own bad reviews would leave the ratings worth nothing to
the people they exist to inform.
"""

from datetime import timedelta

from django.contrib.auth.models import User
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import (
    Establishment,
    MerchantMembership,
    Review,
    Space,
)
from reservations.models import Reservation


class MerchantReviewTestBase(APITestCase):
    def setUp(self):
        self.venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.other = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre',
        )
        self.table = Space.objects.create(
            establishment=self.venue, name='Table 4', capacity=4
        )

        self.owner = self.member('amadou', MerchantMembership.Role.OWNER)
        self.manager = self.member('ibrahima', MerchantMembership.Role.MANAGER)
        self.floor = self.member('aissatou', MerchantMembership.Role.STAFF)
        self.outsider = User.objects.create_user(
            'outsider', password='pw-for-tests'
        )

    def member(self, username, role, establishment=None):
        user = User.objects.create_user(username, password='pw-for-tests')
        MerchantMembership.objects.create(
            user=user,
            establishment=establishment or self.venue,
            role=role,
        )
        return user

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def review(self, rating=5, comment='Lovely', hidden=False, days_ago=1):
        booking = Reservation.objects.create(
            space=self.table,
            customer_name='Mariama',
            customer_phone='+224620000000',
            datetime=timezone.now() - timedelta(days=days_ago),
            party_size=2,
            status=Reservation.Status.COMPLETED,
        )
        return Review.objects.create(
            establishment=self.venue,
            reservation=booking,
            rating=rating,
            comment=comment,
            is_hidden=hidden,
        )

    def list_url(self, establishment=None):
        return reverse(
            'merchant-reviews', args=[(establishment or self.venue).pk]
        )

    def flag_url(self, review, establishment=None):
        return reverse(
            'merchant-review-flag',
            args=[(establishment or self.venue).pk, review.pk],
        )


class ReadingTests(MerchantReviewTestBase):
    def test_an_owner_can_read_their_reviews(self):
        self.review(rating=4, comment='Good chicha')
        self.authenticate(self.owner)

        response = self.client.get(self.list_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['results'][0]['comment'], 'Good chicha')

    def test_staff_can_read_them_too(self):
        """Knowing what customers said is floor knowledge, not a privilege."""
        self.review()
        self.authenticate(self.floor)

        response = self.client.get(self.list_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_a_non_member_is_told_nothing(self):
        self.review()
        self.authenticate(self.outsider)

        response = self.client.get(self.list_url())

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_signed_out_caller_is_refused(self):
        response = self.client.get(self.list_url())

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_hidden_reviews_are_shown_to_the_venue_and_marked(self):
        """A merchant should know one was taken down, and why it is missing
        from their average."""
        self.review(rating=1, comment='Rude staff', hidden=True)
        self.authenticate(self.owner)

        response = self.client.get(self.list_url())

        self.assertEqual(len(response.data['results']), 1)
        self.assertTrue(response.data['results'][0]['is_hidden'])

    def test_another_venues_reviews_are_not_included(self):
        self.review()
        fatou_owner = self.member(
            'fatou', MerchantMembership.Role.OWNER, establishment=self.other
        )
        self.authenticate(fatou_owner)

        response = self.client.get(self.list_url(establishment=self.other))

        self.assertEqual(response.data['results'], [])

    def test_the_spread_is_reported_not_just_the_average(self):
        """One angry two-star among forty fives is a different business from
        a steady drift downwards."""
        self.review(rating=5, days_ago=1)
        self.review(rating=5, days_ago=2)
        self.review(rating=2, days_ago=3)
        self.authenticate(self.owner)

        response = self.client.get(self.list_url())

        self.assertEqual(response.data['distribution']['5'], 2)
        self.assertEqual(response.data['distribution']['2'], 1)
        self.assertEqual(response.data['distribution']['1'], 0)

    def test_a_hidden_review_is_left_out_of_the_average(self):
        self.review(rating=5, days_ago=1)
        self.review(rating=1, days_ago=2, hidden=True)
        self.authenticate(self.owner)

        response = self.client.get(self.list_url())

        self.assertEqual(response.data['average_rating'], 5.0)
        self.assertEqual(response.data['distribution']['1'], 0)

    def test_the_customer_name_is_only_a_first_name(self):
        """Same rule the public list follows; the venue gets no more."""
        self.review()
        self.authenticate(self.owner)

        response = self.client.get(self.list_url())

        self.assertNotIn('customer_phone', response.data['results'][0])


class FlaggingTests(MerchantReviewTestBase):
    def test_an_owner_can_ask_for_one_to_be_looked_at(self):
        review = self.review(rating=1, comment='Never went there')
        self.authenticate(self.owner)

        response = self.client.post(
            self.flag_url(review),
            {'reason': 'This customer never came in.'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        review.refresh_from_db()
        self.assertIsNotNone(review.flagged_at)
        self.assertEqual(review.flagged_reason, 'This customer never came in.')

    def test_a_manager_can_too(self):
        review = self.review(rating=1)
        self.authenticate(self.manager)

        response = self.client.post(
            self.flag_url(review), {'reason': 'Not us.'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_staff_cannot(self):
        """Disputing what a customer said is how the venue answers the
        public, which is the same class of thing as its description."""
        review = self.review(rating=1)
        self.authenticate(self.floor)

        response = self.client.post(
            self.flag_url(review), {'reason': 'Not us.'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        review.refresh_from_db()
        self.assertIsNone(review.flagged_at)

    def test_flagging_needs_a_reason(self):
        """An unexplained flag is work for an admin with nothing to go on."""
        review = self.review(rating=1)
        self.authenticate(self.owner)

        response = self.client.post(
            self.flag_url(review), {'reason': '   '}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        review.refresh_from_db()
        self.assertIsNone(review.flagged_at)

    def test_flagging_twice_is_refused(self):
        review = self.review(rating=1)
        self.authenticate(self.owner)
        self.client.post(
            self.flag_url(review), {'reason': 'First.'}, format='json'
        )

        response = self.client.post(
            self.flag_url(review), {'reason': 'Again.'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        review.refresh_from_db()
        self.assertEqual(review.flagged_reason, 'First.')

    def test_another_venues_review_cannot_be_flagged(self):
        review = self.review(rating=1)
        fatou_owner = self.member(
            'fatou', MerchantMembership.Role.OWNER, establishment=self.other
        )
        self.authenticate(fatou_owner)

        response = self.client.post(
            self.flag_url(review, establishment=self.other),
            {'reason': 'Nothing to do with me.'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        review.refresh_from_db()
        self.assertIsNone(review.flagged_at)


class FlaggingChangesNothingPublicTests(MerchantReviewTestBase):
    """**The property that keeps the ratings worth reading.**

    A merchant asking for a review to be looked at must not, by itself, take
    it down. Otherwise "flag" is "delete" with extra steps and a venue can
    quietly clear its own record.
    """

    def test_a_flagged_review_is_still_shown_to_customers(self):
        review = self.review(rating=1, comment='Slow service')
        self.authenticate(self.owner)
        self.client.post(
            self.flag_url(review), {'reason': 'Unfair.'}, format='json'
        )
        self.client.credentials()

        response = self.client.get(
            reverse('establishment-reviews', args=[self.venue.pk])
        )

        comments = [r['comment'] for r in response.data['results']]
        self.assertIn('Slow service', comments)

    def test_a_flagged_review_still_counts_towards_the_average(self):
        self.review(rating=5, days_ago=1)
        review = self.review(rating=1, days_ago=2)
        self.authenticate(self.owner)
        self.client.post(
            self.flag_url(review), {'reason': 'Unfair.'}, format='json'
        )

        self.venue.refresh_from_db()

        self.assertEqual(self.venue.average_rating, 3.0)

    def test_flagging_does_not_set_is_hidden(self):
        review = self.review(rating=1)
        self.authenticate(self.owner)

        self.client.post(
            self.flag_url(review), {'reason': 'Unfair.'}, format='json'
        )

        review.refresh_from_db()
        self.assertFalse(review.is_hidden)

    def test_a_merchant_cannot_hide_one_directly(self):
        """There is no endpoint for it, and there should not be."""
        review = self.review(rating=1)
        self.authenticate(self.owner)

        response = self.client.post(
            self.flag_url(review),
            {'reason': 'Unfair.', 'is_hidden': True},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        review.refresh_from_db()
        self.assertFalse(
            review.is_hidden,
            'a merchant set is_hidden by passing it in the flag body',
        )

    def test_an_admin_hiding_it_does_take_it_down(self):
        """The other half: moderation still works, it is just not the
        venue's to do."""
        review = self.review(rating=1, comment='Slow service')
        review.is_hidden = True
        review.save(update_fields=['is_hidden'])

        response = self.client.get(
            reverse('establishment-reviews', args=[self.venue.pk])
        )

        self.assertEqual(response.data['results'], [])
