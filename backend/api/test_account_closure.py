"""Keeping a customer's details current, and closing their account.

Two things pull against each other here. A customer who asks to be forgotten
should be forgotten. And a venue's takings for last March are the venue's
record — deleting a booking because the person who made it closed their
account would quietly rewrite somebody else's revenue.

So the tests that matter most are the pair that check both at once: the
booking survives with its money intact, and carries nothing that says whose
it was.
"""

from datetime import timedelta
from decimal import Decimal

from accounts.models import CustomerProfile, PasswordResetCode
from django.contrib.auth.models import User
from django.urls import reverse
from django.utils import timezone
from orders.models import Order
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.favourites import Favourite
from establishments.models import (
    Establishment,
    MerchantMembership,
    Review,
    Space,
)
from payments.models import Payment
from reservations.models import Reservation


class AccountTestBase(APITestCase):
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
        self.user = User.objects.create_user(
            'mariama', password='chicha-2026', first_name='Mariama'
        )
        CustomerProfile.objects.create(user=self.user, phone='+224620000000')
        self.authenticate(self.user)

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def booking(self, days_ago=30, paid=False):
        reservation = Reservation.objects.create(
            space=self.table,
            customer=self.user,
            customer_name='Mariama Diallo',
            customer_phone='+224620000000',
            datetime=timezone.now() - timedelta(days=days_ago),
            party_size=2,
            status=Reservation.Status.COMPLETED,
        )
        if paid:
            Payment.objects.create(
                reservation=reservation,
                provider=Payment.Provider.ORANGE_MONEY,
                amount=Decimal('50000.00'),
                status=Payment.Status.COMPLETED,
                provider_reference='SEED-CLOSURE',
            )
        return reservation


class ProfileTests(AccountTestBase):
    def test_a_customer_can_change_their_name(self):
        response = self.client.patch(
            reverse('customer-me'), {'name': 'Mariama D.'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.first_name, 'Mariama D.')

    def test_a_customer_can_change_their_number(self):
        """Until now this was captured per booking and never maintained."""
        self.client.patch(
            reverse('customer-me'), {'phone': '+224620111111'}, format='json'
        )

        self.assertEqual(
            CustomerProfile.objects.get(user=self.user).phone, '+224620111111'
        )

    def test_adding_a_number_makes_a_reset_possible(self):
        """The reason the field is worth maintaining at all."""
        user = User.objects.create_user('alone', password='x' * 10)
        CustomerProfile.objects.create(user=user, phone='')
        self.authenticate(user)

        before = self.client.get(reverse('customer-me')).data
        self.client.patch(
            reverse('customer-me'), {'phone': '+224620222222'}, format='json'
        )
        after = self.client.get(reverse('customer-me')).data

        self.assertFalse(before['can_reset_password'])
        self.assertTrue(after['can_reset_password'])

    def test_the_username_cannot_be_changed(self):
        """It is what somebody signs in with; letting it move turns "I cannot
        get in" into a conversation nobody can settle."""
        self.client.patch(
            reverse('customer-me'), {'username': 'someone-else'}, format='json'
        )

        self.user.refresh_from_db()
        self.assertEqual(self.user.username, 'mariama')

    def test_a_signed_out_caller_cannot_change_anything(self):
        self.client.credentials()

        response = self.client.patch(
            reverse('customer-me'), {'name': 'Nobody'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class ClosureTests(AccountTestBase):
    def close(self, password='chicha-2026'):
        return self.client.delete(
            reverse('customer-me'), {'password': password}, format='json'
        )

    def test_an_account_can_be_closed(self):
        response = self.close()

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(username='mariama').exists())

    def test_the_password_is_asked_for_again(self):
        """The token on this phone may not be in the hands of the person it
        belongs to, and this is the one action that cannot be undone."""
        response = self.close(password='wrong')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(username='mariama').exists())

    def test_a_signed_out_caller_cannot_close_anything(self):
        self.client.credentials()

        response = self.close()

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_the_things_that_are_only_about_the_person_go(self):
        Favourite.objects.create(user=self.user, establishment=self.venue)
        PasswordResetCode.issue(self.user, 'sms', '+224620000000')

        self.close()

        self.assertFalse(CustomerProfile.objects.exists())
        self.assertFalse(Favourite.objects.exists())
        self.assertFalse(PasswordResetCode.objects.exists())
        self.assertFalse(Token.objects.filter(user_id=self.user.pk).exists())

    def test_a_merchant_account_is_not_closed_here(self):
        """Closing it would take somebody's staff access with it, and that is
        the venue owner's decision."""
        MerchantMembership.objects.create(
            user=self.user,
            establishment=self.venue,
            role=MerchantMembership.Role.STAFF,
        )

        response = self.close()

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertTrue(User.objects.filter(username='mariama').exists())


class WhatSurvivesTests(AccountTestBase):
    """**The pair that matter.** The person goes; the venue's books stay."""

    def close(self):
        return self.client.delete(
            reverse('customer-me'),
            {'password': 'chicha-2026'},
            format='json',
        )

    def test_a_past_booking_survives(self):
        booking = self.booking()

        self.close()

        booking.refresh_from_db()
        self.assertEqual(booking.status, Reservation.Status.COMPLETED)
        self.assertEqual(booking.party_size, 2)

    def test_and_carries_nothing_that_says_whose_it_was(self):
        booking = self.booking()

        self.close()

        booking.refresh_from_db()
        self.assertEqual(booking.customer_name, '')
        self.assertEqual(booking.customer_phone, '')
        self.assertIsNone(booking.customer)

    def test_the_money_is_still_the_venue_s(self):
        """Deleting a booking because its customer left would rewrite
        somebody else's revenue."""
        self.booking(paid=True)

        self.close()

        payment = Payment.objects.get()
        self.assertEqual(payment.amount, Decimal('50000.00'))
        self.assertEqual(payment.status, Payment.Status.COMPLETED)

    def test_it_still_counts_on_the_merchant_dashboard(self):
        self.booking(days_ago=5, paid=True)
        owner = User.objects.create_user('amadou', password='pw-for-tests')
        MerchantMembership.objects.create(
            user=owner,
            establishment=self.venue,
            role=MerchantMembership.Role.OWNER,
        )

        self.close()

        self.authenticate(owner)
        today = timezone.localdate()
        response = self.client.get(
            reverse('payment-dashboard'),
            {
                'establishment': self.venue.pk,
                'date_from': (today - timedelta(days=30)).isoformat(),
                'date_to': today.isoformat(),
            },
        )

        self.assertEqual(
            Decimal(response.data['payments']['collected']),
            Decimal('50000.00'),
        )
        self.assertEqual(response.data['reservations']['total'], 1)

    def test_an_order_is_scrubbed_the_same_way(self):
        order = Order.objects.create(
            establishment=self.venue,
            customer=self.user,
            customer_name='Mariama Diallo',
            customer_phone='+224620000000',
            pickup_time=timezone.now() - timedelta(days=2),
        )

        self.close()

        order.refresh_from_db()
        self.assertEqual(order.customer_name, '')
        self.assertEqual(order.customer_phone, '')
        self.assertIsNone(order.customer)

    def test_a_review_stays_and_still_counts(self):
        """A rating that vanished with its author would let anybody launder a
        venue's score: sign up, review, leave."""
        booking = self.booking()
        Review.objects.create(
            establishment=self.venue,
            reservation=booking,
            rating=2,
            comment='Slow service',
        )

        self.close()

        self.assertEqual(Review.objects.count(), 1)
        self.venue.refresh_from_db()
        self.assertEqual(self.venue.average_rating, 2.0)

    def test_the_review_no_longer_names_anybody(self):
        booking = self.booking()
        Review.objects.create(
            establishment=self.venue,
            reservation=booking,
            rating=2,
            comment='Slow service',
        )

        self.close()
        # The token went with the account, so ask as the public does.
        self.client.credentials()

        response = self.client.get(
            reverse('establishment-reviews', args=[self.venue.pk])
        )

        review = response.data['results'][0]
        self.assertEqual(review['comment'], 'Slow service')
        # The public serializer calls it `author`, and it is a first name
        # only even before any of this.
        self.assertNotIn('Mariama', review['author'])
        self.assertEqual(review['author'], 'Guest')

    def test_another_customer_is_untouched(self):
        other = User.objects.create_user('ibrahima', password='x' * 10)
        theirs = Reservation.objects.create(
            space=self.table,
            customer=other,
            customer_name='Ibrahima Bah',
            customer_phone='+224620999999',
            datetime=timezone.now() - timedelta(days=3),
            party_size=2,
            status=Reservation.Status.COMPLETED,
        )
        self.booking()

        self.close()

        theirs.refresh_from_db()
        self.assertEqual(theirs.customer_name, 'Ibrahima Bah')
        self.assertEqual(theirs.customer, other)
