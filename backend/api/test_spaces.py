"""Laying out a venue's tables and rooms.

Until this existed, a merchant could not enter a single table without Django
admin — the seating plan came only from `seed_demo`. These go at the API
directly: a control hidden in the app is not a permission.

The rule worth reading carefully is deletion. `Reservation.space` is PROTECT,
so a space with history cannot be removed at all; asking to delete one retires
it instead. A venue's past bookings name the table they were on, and
rearranging the room must not rewrite last month.
"""

from datetime import timedelta

from django.contrib.auth.models import User
from django.db.models import ProtectedError
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, MerchantMembership, Space
from reservations.availability import availability_for_establishment
from reservations.models import Reservation


class SpaceTestBase(APITestCase):
    def setUp(self):
        self.baobab = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.fatou = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre-ville',
        )

        self.owner = self.member('amadou', self.baobab, MerchantMembership.Role.OWNER)
        self.manager = self.member(
            'ibrahima', self.baobab, MerchantMembership.Role.MANAGER
        )
        self.floor = self.member(
            'aissatou', self.baobab, MerchantMembership.Role.STAFF
        )
        self.outsider = User.objects.create_user('outsider', password='pw-for-tests')

        self.table = Space.objects.create(
            establishment=self.baobab,
            name='Table 4',
            type=Space.Type.TABLE,
            capacity=4,
        )

    def member(self, username, establishment, role):
        user = User.objects.create_user(username, password='pw-for-tests')
        MerchantMembership.objects.create(
            user=user, establishment=establishment, role=role
        )
        return user

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def list_url(self, establishment=None):
        return reverse(
            'merchant-spaces', args=[(establishment or self.baobab).pk]
        )

    def item_url(self, space, establishment=None):
        return reverse(
            'merchant-space-item',
            args=[(establishment or self.baobab).pk, space.pk],
        )

    def book(self, space, when=None, status_=Reservation.Status.CONFIRMED):
        return Reservation.objects.create(
            space=space,
            customer_name='Mariama',
            customer_phone='+224620000000',
            datetime=when or (timezone.now() + timedelta(days=1)),
            party_size=2,
            status=status_,
        )


class SpaceAccessTests(SpaceTestBase):
    def test_an_owner_can_add_a_space(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.list_url(),
            {'name': 'VIP Room 1', 'type': 'vip_room', 'capacity': 8},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['name'], 'VIP Room 1')
        self.assertTrue(response.data['is_active'])
        self.assertEqual(self.baobab.spaces.count(), 2)

    def test_a_manager_can_add_a_space(self):
        self.authenticate(self.manager)

        response = self.client.post(
            self.list_url(),
            {'name': 'Terrace', 'type': 'terrace', 'capacity': 10},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_staff_cannot_add_a_space(self):
        """D3: the layout of the room is structural, like hours and the menu."""
        self.authenticate(self.floor)

        response = self.client.post(
            self.list_url(),
            {'name': 'Table 5', 'type': 'table', 'capacity': 2},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.baobab.spaces.count(), 1)

    def test_staff_can_read_the_layout(self):
        """The desk shows which table a booking is on."""
        self.authenticate(self.floor)

        response = self.client.get(self.list_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['results']), 1)

    def test_a_non_member_is_told_nothing(self):
        """404, not 403 — the same posture as every other merchant route.

        A 403 confirms the venue exists, which is more than someone with no
        business there should learn.
        """
        self.authenticate(self.outsider)

        response = self.client.get(self.list_url())

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_signing_out_is_enough_to_be_refused(self):
        response = self.client.get(self.list_url())

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_a_space_cannot_be_edited_through_another_venues_url(self):
        """The id is real; the path is not this caller's venue."""
        self.authenticate(self.owner)

        response = self.client.patch(
            self.item_url(self.table, establishment=self.fatou),
            {'capacity': 99},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.table.refresh_from_db()
        self.assertEqual(self.table.capacity, 4)


class SpaceValidationTests(SpaceTestBase):
    def test_a_duplicate_name_is_a_field_error(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.list_url(),
            {'name': 'Table 4', 'type': 'table', 'capacity': 2},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('name', response.data)

    def test_a_duplicate_name_is_caught_regardless_of_case(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.list_url(),
            {'name': 'table 4', 'type': 'table', 'capacity': 2},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_the_same_name_in_another_venue_is_fine(self):
        """Two venues both having a Table 4 is normal, not a clash."""
        owner_of_fatou = self.member(
            'fatou', self.fatou, MerchantMembership.Role.OWNER
        )
        self.authenticate(owner_of_fatou)

        response = self.client.post(
            self.list_url(establishment=self.fatou),
            {'name': 'Table 4', 'type': 'table', 'capacity': 4},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_renaming_a_space_to_its_own_name_is_allowed(self):
        """The uniqueness check must not count the row against itself."""
        self.authenticate(self.owner)

        response = self.client.patch(
            self.item_url(self.table),
            {'name': 'Table 4', 'capacity': 6},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['capacity'], 6)

    def test_zero_capacity_is_refused(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.list_url(),
            {'name': 'Nowhere', 'type': 'table', 'capacity': 0},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('capacity', response.data)

    def test_negative_capacity_is_refused(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.list_url(),
            {'name': 'Nowhere', 'type': 'table', 'capacity': -3},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_blank_name_is_refused(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.list_url(),
            {'name': '   ', 'type': 'table', 'capacity': 4},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('name', response.data)

    def test_a_space_cannot_be_moved_to_another_establishment(self):
        """`establishment` is not a writable field; the path decides."""
        self.authenticate(self.owner)

        self.client.patch(
            self.item_url(self.table),
            {'establishment': self.fatou.pk},
            format='json',
        )

        self.table.refresh_from_db()
        self.assertEqual(self.table.establishment, self.baobab)


class SpaceDeletionTests(SpaceTestBase):
    """Deletion is the rule most likely to lose data if it is got wrong."""

    def test_a_space_with_no_history_is_really_deleted(self):
        self.authenticate(self.owner)

        response = self.client.delete(self.item_url(self.table))

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Space.objects.filter(pk=self.table.pk).exists())

    def test_the_database_itself_refuses_to_delete_a_booked_space(self):
        """PROTECT is the guard, not a check in the view.

        Written against the ORM rather than the API on purpose: if someone
        later adds a bulk delete, or a management command, this is what stops
        a venue's history going with it.
        """
        self.book(self.table)

        with self.assertRaises(ProtectedError):
            self.table.delete()

        self.assertTrue(Space.objects.filter(pk=self.table.pk).exists())

    def test_deleting_a_booked_space_retires_it_instead(self):
        self.book(self.table)
        self.authenticate(self.owner)

        response = self.client.delete(self.item_url(self.table))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['is_active'])
        # The row survives, which is the whole point.
        self.table.refresh_from_db()
        self.assertFalse(self.table.is_active)

    def test_a_cancelled_booking_still_protects_the_space(self):
        """History is history; a cancellation is part of it."""
        self.book(self.table, status_=Reservation.Status.CANCELLED)
        self.authenticate(self.owner)

        response = self.client.delete(self.item_url(self.table))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(Space.objects.filter(pk=self.table.pk).exists())

    def test_the_booking_on_a_retired_space_is_still_readable(self):
        """What the merchant app's desk and the customer's history both need.

        A retired table must not turn its past bookings into holes.
        """
        reservation = self.book(self.table)
        self.authenticate(self.owner)
        self.client.delete(self.item_url(self.table))

        response = self.client.get(
            reverse('reservation-detail', args=[reservation.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['space_name'], 'Table 4')

    def test_a_customer_can_still_read_their_booking_on_a_retired_space(self):
        reservation = self.book(self.table)
        self.authenticate(self.owner)
        self.client.delete(self.item_url(self.table))
        self.client.credentials()

        response = self.client.get(
            reverse('reservation-by-reference', args=[reservation.reference])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['space_name'], 'Table 4')

    def test_staff_cannot_retire_a_space(self):
        self.book(self.table)
        self.authenticate(self.floor)

        response = self.client.delete(self.item_url(self.table))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.table.refresh_from_db()
        self.assertTrue(self.table.is_active)

    def test_a_retired_space_can_be_brought_back(self):
        """A table out for repairs comes back; it is not a one-way door."""
        self.book(self.table)
        self.authenticate(self.owner)
        self.client.delete(self.item_url(self.table))

        response = self.client.patch(
            self.item_url(self.table), {'is_active': True}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_active'])


class RetiredSpaceVisibilityTests(SpaceTestBase):
    def setUp(self):
        super().setUp()
        self.retired = Space.objects.create(
            establishment=self.baobab,
            name='Old Corner',
            type=Space.Type.TABLE,
            capacity=2,
            is_active=False,
        )

    def test_availability_offers_no_slots_on_a_retired_space(self):
        grid = availability_for_establishment(
            self.baobab, (timezone.now() + timedelta(days=1)).date()
        )

        names = [row['space'].name for row in grid]
        self.assertIn('Table 4', names)
        self.assertNotIn('Old Corner', names)

    def test_the_customer_detail_payload_omits_a_retired_space(self):
        response = self.client.get(
            reverse('establishment-detail', args=[self.baobab.pk])
        )

        names = [space['name'] for space in response.data['spaces']]
        self.assertEqual(names, ['Table 4'])

    def test_the_merchant_list_still_shows_it(self):
        """A merchant needs to see what they retired, to bring it back."""
        self.authenticate(self.owner)

        response = self.client.get(self.list_url())

        names = {space['name'] for space in response.data['results']}
        self.assertEqual(names, {'Table 4', 'Old Corner'})

    def test_booking_a_retired_space_is_refused(self):
        """A stale screen, or a direct call. Either way the table is gone."""
        response = self.client.post(
            reverse('reservation-list'),
            {
                'space': self.retired.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'datetime': (timezone.now() + timedelta(days=1)).isoformat(),
                'party_size': 2,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('space', response.data)

    def test_an_existing_booking_on_a_retired_space_still_holds_its_slot(self):
        """The sitting is still happening; only new bookings are barred."""
        when = timezone.now() + timedelta(days=1)
        self.book(self.retired, when=when)

        from reservations.availability import is_space_available

        self.assertFalse(is_space_available(self.retired, when))
