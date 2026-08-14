"""Optional customer accounts.

The rule under all of these: the app worked without an account before, and it
still has to. Every test that grants something to a signed-in customer has a
sibling proving the signed-out path is untouched.
"""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from orders.models import Order
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.favourites import Favourite
from establishments.models import Establishment, Space
from reservations.models import Reservation

User = get_user_model()


class CustomerAccountTestCase(APITestCase):
    def setUp(self):
        self.lounge = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.restaurant = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Kaloum',
        )
        self.space = Space.objects.create(
            establishment=self.lounge, name='Table 4', capacity=4
        )

    def register(self, username='mariama', password='chicha-2026', name='Mariama'):
        return self.client.post(
            reverse('customer-register'),
            {'username': username, 'password': password, 'name': name},
            format='json',
        )

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def book(self, **extra):
        return Reservation.objects.create(
            space=self.space,
            customer_name='Mariama Diallo',
            customer_phone='+224620000000',
            datetime=timezone.now() + timedelta(days=1),
            party_size=2,
            **extra,
        )


class RegisteringTests(CustomerAccountTestCase):
    def test_signing_up_returns_a_token(self):
        response = self.register()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['token'])
        self.assertEqual(response.data['user']['name'], 'Mariama')

    def test_the_name_is_taken_message_is_actionable(self):
        self.register()

        response = self.register()

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('taken', str(response.data['username']))

    def test_the_name_check_ignores_case(self):
        self.register(username='mariama')

        response = self.register(username='MARIAMA')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_short_password_is_refused(self):
        response = self.register(password='short')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_the_password_is_hashed_not_stored(self):
        self.register(password='chicha-2026')

        user = User.objects.get(username='mariama')
        self.assertNotEqual(user.password, 'chicha-2026')
        self.assertTrue(user.check_password('chicha-2026'))

    def test_a_new_account_can_sign_in_through_the_normal_route(self):
        self.register(password='chicha-2026')

        response = self.client.post(
            reverse('auth-login'),
            {'username': 'mariama', 'password': 'chicha-2026'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_me_needs_a_token(self):
        response = self.client.get(reverse('customer-me'))

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class BookingWithoutAnAccountTests(CustomerAccountTestCase):
    """The path that must never regress."""

    def test_a_booking_needs_no_account(self):
        response = self.client.post(
            reverse('reservation-list'),
            {
                'space': self.space.pk,
                'customer_name': 'Mariama Diallo',
                'customer_phone': '+224620000000',
                'datetime': (
                    timezone.now() + timedelta(days=1)
                ).isoformat(),
                'party_size': 2,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIsNone(
            Reservation.objects.get(pk=response.data['id']).customer
        )

    def test_the_reference_still_works_with_no_account(self):
        booking = self.book()

        response = self.client.get(
            reverse('reservation-by-reference', args=[booking.reference])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class ClaimingTests(CustomerAccountTestCase):
    def test_signing_up_can_adopt_this_phones_bookings(self):
        booking = self.book()
        registered = self.register()
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Token {registered.data["token"]}'
        )

        response = self.client.post(
            reverse('customer-claim'),
            {'reservation_references': [str(booking.reference)]},
            format='json',
        )

        self.assertEqual(response.data['reservations'], 1)
        booking.refresh_from_db()
        self.assertEqual(booking.customer.username, 'mariama')

    def test_orders_are_adopted_too(self):
        order = Order.objects.create(
            establishment=self.restaurant,
            customer_name='Mariama',
            customer_phone='+224620000000',
            pickup_time=timezone.now() + timedelta(hours=2),
        )
        registered = self.register()
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Token {registered.data["token"]}'
        )

        response = self.client.post(
            reverse('customer-claim'),
            {'order_references': [str(order.reference)]},
            format='json',
        )

        self.assertEqual(response.data['orders'], 1)

    def test_somebody_elses_booking_cannot_be_taken(self):
        thief = User.objects.create_user('thief', password='x' * 10)
        owner = User.objects.create_user('owner', password='x' * 10)
        booking = self.book(customer=owner)

        self.authenticate(thief)
        response = self.client.post(
            reverse('customer-claim'),
            {'reservation_references': [str(booking.reference)]},
            format='json',
        )

        # Already claimed, so skipped rather than reassigned.
        self.assertEqual(response.data['reservations'], 0)
        booking.refresh_from_db()
        self.assertEqual(booking.customer, owner)

    def test_claiming_twice_is_harmless(self):
        booking = self.book()
        registered = self.register()
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Token {registered.data["token"]}'
        )
        payload = {'reservation_references': [str(booking.reference)]}

        self.client.post(reverse('customer-claim'), payload, format='json')
        second = self.client.post(
            reverse('customer-claim'), payload, format='json'
        )

        self.assertEqual(second.data['reservations'], 0)

    def test_claiming_needs_a_token(self):
        response = self.client.post(
            reverse('customer-claim'), {}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class HistoryTests(CustomerAccountTestCase):
    def test_the_account_carries_the_history(self):
        user = User.objects.create_user('mariama', password='x' * 10)
        self.book(customer=user)
        self.authenticate(user)

        response = self.client.get(reverse('customer-history'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['reservations']), 1)

    def test_it_shows_only_your_own(self):
        mine = User.objects.create_user('mine', password='x' * 10)
        theirs = User.objects.create_user('theirs', password='x' * 10)
        self.book(customer=theirs)
        self.authenticate(mine)

        response = self.client.get(reverse('customer-history'))

        self.assertEqual(len(response.data['reservations']), 0)

    def test_unclaimed_bookings_belong_to_nobody(self):
        user = User.objects.create_user('mariama', password='x' * 10)
        self.book()
        self.authenticate(user)

        response = self.client.get(reverse('customer-history'))

        self.assertEqual(len(response.data['reservations']), 0)


class FavouriteTests(CustomerAccountTestCase):
    def setUp(self):
        super().setUp()
        self.user = User.objects.create_user('mariama', password='x' * 10)
        self.authenticate(self.user)

    def test_a_venue_can_be_saved(self):
        response = self.client.post(
            reverse('customer-favourites'),
            {'establishment': self.lounge.pk},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['results']), 1)
        self.assertEqual(response.data['results'][0]['name'], 'Le Petit Baobab')

    def test_saving_twice_keeps_one(self):
        payload = {'establishment': self.lounge.pk}
        self.client.post(reverse('customer-favourites'), payload, format='json')
        response = self.client.post(
            reverse('customer-favourites'), payload, format='json'
        )

        self.assertEqual(len(response.data['results']), 1)
        self.assertEqual(Favourite.objects.count(), 1)

    def test_a_whole_list_can_be_merged_up_from_a_phone(self):
        response = self.client.post(
            reverse('customer-favourites'),
            {'establishments': [self.lounge.pk, self.restaurant.pk]},
            format='json',
        )

        self.assertEqual(len(response.data['results']), 2)

    def test_merging_adds_rather_than_replaces(self):
        self.client.post(
            reverse('customer-favourites'),
            {'establishment': self.lounge.pk},
            format='json',
        )

        # A second phone signs in carrying a different list.
        response = self.client.post(
            reverse('customer-favourites'),
            {'establishments': [self.restaurant.pk]},
            format='json',
        )

        self.assertEqual(len(response.data['results']), 2)

    def test_a_venue_can_be_unsaved(self):
        self.client.post(
            reverse('customer-favourites'),
            {'establishment': self.lounge.pk},
            format='json',
        )

        response = self.client.delete(
            reverse('customer-favourite-detail', args=[self.lounge.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(Favourite.objects.count(), 0)

    def test_unsaving_something_never_saved_is_not_an_error(self):
        response = self.client.delete(
            reverse('customer-favourite-detail', args=[self.restaurant.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

    def test_a_venue_that_does_not_exist_is_ignored(self):
        response = self.client.post(
            reverse('customer-favourites'),
            {'establishments': [self.lounge.pk, 9999]},
            format='json',
        )

        self.assertEqual(len(response.data['results']), 1)

    def test_favourites_are_private_to_the_account(self):
        self.client.post(
            reverse('customer-favourites'),
            {'establishment': self.lounge.pk},
            format='json',
        )

        other = User.objects.create_user('other', password='x' * 10)
        self.authenticate(other)
        response = self.client.get(reverse('customer-favourites'))

        self.assertEqual(len(response.data['results']), 0)

    def test_favourites_need_an_account(self):
        self.client.credentials()

        response = self.client.get(reverse('customer-favourites'))

        # Signed out, the list lives on the phone instead — the server has
        # nothing to say.
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_saying_nothing_to_save_is_refused(self):
        response = self.client.post(
            reverse('customer-favourites'), {}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
