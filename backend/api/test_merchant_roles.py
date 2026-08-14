"""Roles, venue scoping, and the merchant-editable endpoints.

Every permission test goes at the API directly. A control hidden in the app is
not a permission; the point is what the server does when the request arrives
anyway.
"""

from datetime import time
from decimal import Decimal

from django.contrib.auth.models import User
from django.urls import reverse
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import (
    Establishment,
    MenuItem,
    MerchantMembership,
    OpeningHours,
)


class RoleTestBase(APITestCase):
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
        self.outsider = User.objects.create_user(
            'outsider', password='pw-for-tests'
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

    def hours_url(self, establishment=None):
        return reverse(
            'merchant-hours', args=[(establishment or self.baobab).pk]
        )

    def menu_url(self, establishment=None):
        return reverse('merchant-menu', args=[(establishment or self.baobab).pk])

    def profile_url(self, establishment=None):
        return reverse(
            'merchant-establishment-profile',
            args=[(establishment or self.baobab).pk],
        )

    def staff_url(self, establishment=None):
        return reverse('merchant-staff', args=[(establishment or self.baobab).pk])

    def a_week(self):
        return [
            {
                'day_of_week': day,
                'is_closed': False,
                'opens': '18:00',
                'closes': '02:00',
            }
            for day in range(7)
        ]


class MigrationOutcomeTests(RoleTestBase):
    """Existing access must survive the move to roles."""

    def test_a_membership_grants_the_same_access_as_before(self):
        self.authenticate(self.floor)

        response = self.client.get(
            f'{reverse("reservation-list")}?establishment={self.baobab.pk}'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_the_staff_m2m_still_resolves_through_the_membership(self):
        self.assertIn(self.owner, self.baobab.staff.all())
        self.assertEqual(self.baobab.staff.count(), 3)

    def test_adding_via_the_m2m_defaults_to_the_least_privilege(self):
        """A bare .add() must not silently mint an owner."""
        newcomer = User.objects.create_user('newcomer', password='pw-for-tests')
        self.baobab.staff.add(newcomer)

        membership = MerchantMembership.objects.get(
            user=newcomer, establishment=self.baobab
        )
        self.assertEqual(membership.role, MerchantMembership.Role.STAFF)


class VenueListTests(RoleTestBase):
    def test_it_lists_only_the_callers_venues_with_roles(self):
        MerchantMembership.objects.create(
            user=self.owner,
            establishment=self.fatou,
            role=MerchantMembership.Role.MANAGER,
        )
        self.authenticate(self.owner)

        rows = self.client.get(reverse('merchant-establishments')).data['results']
        by_name = {row['name']: row for row in rows}

        self.assertEqual(set(by_name), {'Le Petit Baobab', 'Chez Fatou'})
        self.assertEqual(by_name['Le Petit Baobab']['role'], 'owner')
        self.assertEqual(by_name['Chez Fatou']['role'], 'manager')

    def test_a_single_venue_user_gets_exactly_one(self):
        self.authenticate(self.floor)

        rows = self.client.get(reverse('merchant-establishments')).data['results']

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['role'], 'staff')

    def test_capability_flags_match_the_role(self):
        self.authenticate(self.floor)
        row = self.client.get(reverse('merchant-establishments')).data['results'][0]

        self.assertFalse(row['can_edit_profile'])
        self.assertFalse(row['can_manage_staff'])

    def test_a_user_with_no_venues_gets_an_empty_list(self):
        self.authenticate(self.outsider)

        rows = self.client.get(reverse('merchant-establishments')).data['results']

        self.assertEqual(rows, [])

    def test_creating_a_venue_makes_the_creator_its_owner(self):
        self.authenticate(self.outsider)

        response = self.client.post(
            reverse('merchant-establishments'),
            {
                'name': 'Nouveau Lounge',
                'type': 'lounge',
                'city': 'Conakry',
                'address': 'Ratoma',
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        membership = MerchantMembership.objects.get(
            user=self.outsider, establishment_id=response.data['id']
        )
        self.assertEqual(membership.role, MerchantMembership.Role.OWNER)

    def test_creating_a_venue_requires_a_login(self):
        self.client.credentials()

        response = self.client.post(
            reverse('merchant-establishments'),
            {'name': 'X', 'type': 'lounge', 'city': 'Y', 'address': 'Z'},
            format='json',
        )

        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )


class ProfileEditingTests(RoleTestBase):
    """Owner and manager may edit the venue. Staff may not."""

    def test_an_owner_can_edit(self):
        self.authenticate(self.owner)

        response = self.client.patch(
            self.profile_url(), {'tagline': 'Rooftop chicha'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.baobab.refresh_from_db()
        self.assertEqual(self.baobab.tagline, 'Rooftop chicha')

    def test_a_manager_can_edit(self):
        self.authenticate(self.manager)

        response = self.client.patch(
            self.profile_url(), {'description': 'A quiet terrace.'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_staff_cannot_edit_even_by_direct_api_call(self):
        self.authenticate(self.floor)

        response = self.client.patch(
            self.profile_url(), {'tagline': 'Hacked'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.baobab.refresh_from_db()
        self.assertEqual(self.baobab.tagline, '')

    def test_a_non_member_gets_404_not_403(self):
        """Confirming the venue exists tells an outsider more than they need."""
        self.authenticate(self.outsider)

        response = self.client.patch(
            self.profile_url(), {'tagline': 'Nope'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_an_owner_of_one_venue_cannot_edit_another(self):
        self.authenticate(self.owner)

        response = self.client.patch(
            self.profile_url(self.fatou), {'tagline': 'Nope'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_staff_can_still_read_the_profile(self):
        self.authenticate(self.floor)

        self.assertEqual(
            self.client.get(self.profile_url()).status_code, status.HTTP_200_OK
        )


class HoursEditingTests(RoleTestBase):
    def test_an_owner_can_replace_the_week(self):
        self.authenticate(self.owner)

        response = self.client.put(
            self.hours_url(), self.a_week(), format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.baobab.hours.count(), 7)

    def test_a_manager_can_too(self):
        self.authenticate(self.manager)

        response = self.client.put(
            self.hours_url(), self.a_week(), format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_staff_cannot(self):
        self.authenticate(self.floor)

        response = self.client.put(
            self.hours_url(), self.a_week(), format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.baobab.hours.count(), 0)

    def test_a_non_member_cannot(self):
        self.authenticate(self.outsider)

        response = self.client.put(
            self.hours_url(), self.a_week(), format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_hours_cannot_be_written_to_another_venue(self):
        self.authenticate(self.owner)

        response = self.client.put(
            self.hours_url(self.fatou), self.a_week(), format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(self.fatou.hours.count(), 0)

    def test_an_open_day_needs_both_times(self):
        self.authenticate(self.owner)

        response = self.client.put(
            self.hours_url(),
            [{'day_of_week': 0, 'is_closed': False, 'opens': '18:00'}],
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_repeated_weekday_is_rejected(self):
        self.authenticate(self.owner)

        response = self.client.put(
            self.hours_url(),
            [
                {'day_of_week': 0, 'is_closed': True},
                {'day_of_week': 0, 'is_closed': False, 'opens': '18:00',
                 'closes': '02:00'},
            ],
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_replacing_the_week_does_not_leave_stale_days(self):
        OpeningHours.objects.create(
            establishment=self.baobab,
            day_of_week=3,
            opens=time(9, 0),
            closes=time(17, 0),
        )
        self.authenticate(self.owner)

        self.client.put(
            self.hours_url(),
            [{'day_of_week': 0, 'is_closed': True}],
            format='json',
        )

        self.assertEqual(self.baobab.hours.count(), 1)
        self.assertEqual(self.baobab.hours.first().day_of_week, 0)


class MenuEditingTests(RoleTestBase):
    def add_item(self, available=True):
        return MenuItem.objects.create(
            establishment=self.baobab,
            name='Poulet braisé',
            category=MenuItem.Category.FOOD,
            price=Decimal('75000'),
            is_available=available,
        )

    def item_url(self, item):
        return reverse('merchant-menu-item', args=[self.baobab.pk, item.pk])

    def availability_url(self, item):
        return reverse(
            'merchant-menu-availability', args=[self.baobab.pk, item.pk]
        )

    def test_an_owner_can_add_an_item(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.menu_url(),
            {'name': 'Brochettes', 'category': 'food', 'price': '50000'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_a_manager_can_add_an_item(self):
        self.authenticate(self.manager)

        response = self.client.post(
            self.menu_url(),
            {'name': 'Brochettes', 'category': 'food', 'price': '50000'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_staff_cannot_add_an_item(self):
        self.authenticate(self.floor)

        response = self.client.post(
            self.menu_url(),
            {'name': 'Brochettes', 'category': 'food', 'price': '50000'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(MenuItem.objects.count(), 0)

    def test_staff_cannot_edit_an_item(self):
        item = self.add_item()
        self.authenticate(self.floor)

        response = self.client.patch(
            self.item_url(item), {'price': '1'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        item.refresh_from_db()
        self.assertEqual(item.price, Decimal('75000'))

    def test_staff_cannot_delete_an_item(self):
        item = self.add_item()
        self.authenticate(self.floor)

        response = self.client.delete(self.item_url(item))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(MenuItem.objects.count(), 1)

    def test_staff_can_read_the_menu(self):
        """They need to, in order to mark something sold out."""
        self.add_item()
        self.authenticate(self.floor)

        response = self.client.get(self.menu_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['results']), 1)

    def test_an_owner_can_delete_an_item(self):
        item = self.add_item()
        self.authenticate(self.owner)

        response = self.client.delete(self.item_url(item))

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(MenuItem.objects.count(), 0)


class MenuAvailabilityTests(RoleTestBase):
    """The deliberate exception: staff may mark a dish sold out."""

    def setUp(self):
        super().setUp()
        self.item = MenuItem.objects.create(
            establishment=self.baobab,
            name='Poulet braisé',
            category=MenuItem.Category.FOOD,
            price=Decimal('75000'),
            is_available=True,
        )

    def availability_url(self, establishment=None):
        return reverse(
            'merchant-menu-availability',
            args=[(establishment or self.baobab).pk, self.item.pk],
        )

    def toggle(self, available):
        return self.client.patch(
            self.availability_url(), {'is_available': available}, format='json'
        )

    def test_staff_can_mark_an_item_sold_out(self):
        self.authenticate(self.floor)

        response = self.toggle(False)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.item.refresh_from_db()
        self.assertFalse(self.item.is_available)

    def test_staff_can_put_it_back(self):
        self.item.is_available = False
        self.item.save(update_fields=['is_available'])
        self.authenticate(self.floor)

        self.toggle(True)

        self.item.refresh_from_db()
        self.assertTrue(self.item.is_available)

    def test_a_manager_can_too(self):
        self.authenticate(self.manager)
        self.assertEqual(self.toggle(False).status_code, status.HTTP_200_OK)

    def test_an_owner_can_too(self):
        self.authenticate(self.owner)
        self.assertEqual(self.toggle(False).status_code, status.HTTP_200_OK)

    def test_a_non_member_cannot(self):
        self.authenticate(self.outsider)

        response = self.toggle(False)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.item.refresh_from_db()
        self.assertTrue(self.item.is_available)

    def test_the_toggle_cannot_be_used_to_edit_anything_else(self):
        """It is an availability switch, not a back door into the item."""
        self.authenticate(self.floor)

        self.client.patch(
            self.availability_url(),
            {'is_available': False, 'price': '1', 'name': 'Free food'},
            format='json',
        )

        self.item.refresh_from_db()
        self.assertEqual(self.item.price, Decimal('75000'))
        self.assertEqual(self.item.name, 'Poulet braisé')
        self.assertFalse(self.item.is_available)

    def test_the_flag_is_required(self):
        self.authenticate(self.floor)

        response = self.client.patch(
            self.availability_url(), {}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class StaffManagementTests(RoleTestBase):
    """Owner alone. A manager is refused exactly as staff would be."""

    def membership_url(self, membership):
        return reverse(
            'merchant-staff-member', args=[self.baobab.pk, membership.pk]
        )

    def owner_membership(self):
        return MerchantMembership.objects.get(
            user=self.owner, establishment=self.baobab
        )

    def floor_membership(self):
        return MerchantMembership.objects.get(
            user=self.floor, establishment=self.baobab
        )

    def test_an_owner_can_list_the_members(self):
        self.authenticate(self.owner)

        response = self.client.get(self.staff_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['results']), 3)

    def test_a_manager_cannot_list_the_members(self):
        self.authenticate(self.manager)

        response = self.client.get(self.staff_url())

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_an_owner_can_add_a_member(self):
        newcomer = User.objects.create_user('newcomer', password='pw-for-tests')
        self.authenticate(self.owner)

        response = self.client.post(
            self.staff_url(),
            {'username': 'newcomer', 'role': 'staff'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(
            MerchantMembership.objects.filter(
                user=newcomer, establishment=self.baobab
            ).exists()
        )

    def test_a_manager_cannot_add_a_member(self):
        User.objects.create_user('newcomer', password='pw-for-tests')
        self.authenticate(self.manager)

        response = self.client.post(
            self.staff_url(),
            {'username': 'newcomer', 'role': 'staff'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.baobab.memberships.count(), 3)

    def test_staff_cannot_add_a_member(self):
        User.objects.create_user('newcomer', password='pw-for-tests')
        self.authenticate(self.floor)

        response = self.client.post(
            self.staff_url(),
            {'username': 'newcomer', 'role': 'owner'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_manager_cannot_remove_a_member(self):
        self.authenticate(self.manager)

        response = self.client.delete(
            self.membership_url(self.floor_membership())
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.baobab.memberships.count(), 3)

    def test_an_owner_can_remove_a_member(self):
        self.authenticate(self.owner)

        response = self.client.delete(
            self.membership_url(self.floor_membership())
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(self.baobab.memberships.count(), 2)

    def test_a_manager_cannot_change_a_role(self):
        self.authenticate(self.manager)

        response = self.client.patch(
            self.membership_url(self.floor_membership()),
            {'role': 'owner'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_an_owner_can_promote_someone(self):
        self.authenticate(self.owner)

        response = self.client.patch(
            self.membership_url(self.floor_membership()),
            {'role': 'manager'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            self.floor_membership().role, MerchantMembership.Role.MANAGER
        )

    def test_the_last_owner_cannot_be_demoted(self):
        """A venue nobody can administer is not a state worth allowing."""
        self.authenticate(self.owner)

        response = self.client.patch(
            self.membership_url(self.owner_membership()),
            {'role': 'manager'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            self.owner_membership().role, MerchantMembership.Role.OWNER
        )

    def test_the_last_owner_cannot_be_removed(self):
        self.authenticate(self.owner)

        response = self.client.delete(
            self.membership_url(self.owner_membership())
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_owner_can_step_down_once_another_exists(self):
        self.client.credentials()
        MerchantMembership.objects.filter(
            user=self.manager, establishment=self.baobab
        ).update(role=MerchantMembership.Role.OWNER)
        self.authenticate(self.owner)

        response = self.client.patch(
            self.membership_url(self.owner_membership()),
            {'role': 'staff'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_staff_cannot_be_managed_at_another_venue(self):
        self.authenticate(self.owner)

        response = self.client.get(self.staff_url(self.fatou))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_an_unknown_username_is_a_clear_error(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.staff_url(), {'username': 'ghost'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('username', response.data)

    def test_adding_someone_twice_is_refused(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.staff_url(), {'username': 'aissatou'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class RoleChangesTakeEffectImmediatelyTests(RoleTestBase):
    """No re-login required — permissions are read per request."""

    def test_a_promotion_applies_on_the_very_next_request(self):
        self.authenticate(self.floor)
        refused = self.client.patch(
            self.profile_url(), {'tagline': 'Before'}, format='json'
        )
        self.assertEqual(refused.status_code, status.HTTP_403_FORBIDDEN)

        MerchantMembership.objects.filter(
            user=self.floor, establishment=self.baobab
        ).update(role=MerchantMembership.Role.MANAGER)

        # Same token, no re-login.
        allowed = self.client.patch(
            self.profile_url(), {'tagline': 'After'}, format='json'
        )
        self.assertEqual(allowed.status_code, status.HTTP_200_OK)

    def test_a_demotion_applies_on_the_very_next_request(self):
        self.authenticate(self.manager)
        self.assertEqual(
            self.client.patch(
                self.profile_url(), {'tagline': 'Before'}, format='json'
            ).status_code,
            status.HTTP_200_OK,
        )

        MerchantMembership.objects.filter(
            user=self.manager, establishment=self.baobab
        ).update(role=MerchantMembership.Role.STAFF)

        self.assertEqual(
            self.client.patch(
                self.profile_url(), {'tagline': 'After'}, format='json'
            ).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_revoking_access_applies_immediately(self):
        self.authenticate(self.floor)
        MerchantMembership.objects.filter(
            user=self.floor, establishment=self.baobab
        ).delete()

        response = self.client.get(
            f'{reverse("reservation-list")}?establishment={self.baobab.pk}'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
