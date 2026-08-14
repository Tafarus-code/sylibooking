"""Ordering ahead, end to end.

The rules that matter here are all ones a client could otherwise talk its way
around, so every one of them is asserted against the API rather than against a
model method.
"""

from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.db.models import ProtectedError
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from orders.models import Order
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import (
    Establishment,
    MenuItem,
    MerchantMembership,
    Space,
)
from payments.models import Payment
from payments.tests import STUCK
from reservations.models import Reservation

User = get_user_model()


class OrderTestCase(APITestCase):
    """A restaurant with a menu, a lounge, and staff at each role."""

    def setUp(self):
        self.restaurant = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Kaloum',
        )
        self.lounge = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.poulet = MenuItem.objects.create(
            establishment=self.restaurant,
            name='Poulet braisé',
            category=MenuItem.Category.FOOD,
            price=Decimal('75000.00'),
        )
        self.jus = MenuItem.objects.create(
            establishment=self.restaurant,
            name='Jus de gingembre',
            category=MenuItem.Category.DRINK,
            price=Decimal('20000.00'),
        )

        self.owner = User.objects.create_user('amadou', password='x')
        self.staff = User.objects.create_user('sekou', password='x')
        MerchantMembership.objects.create(
            user=self.owner,
            establishment=self.restaurant,
            role=MerchantMembership.Role.OWNER,
        )
        MerchantMembership.objects.create(
            user=self.staff,
            establishment=self.restaurant,
            role=MerchantMembership.Role.STAFF,
        )

    def pickup_time(self, hours=2):
        return timezone.now() + timedelta(hours=hours)

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def place_order(self, establishment=None, provider='cash_on_arrival', **extra):
        payload = {
            'establishment': (establishment or self.restaurant).pk,
            'customer_name': 'Mariama Diallo',
            'customer_phone': '+224620000000',
            'pickup_time': self.pickup_time().isoformat(),
            'items': [
                {'menu_item': self.poulet.pk, 'quantity': 2},
                {'menu_item': self.jus.pk, 'quantity': 1},
            ],
            'payment_provider': provider,
            **extra,
        }
        return self.client.post(reverse('order-create'), payload, format='json')


class PlacingAnOrderTests(OrderTestCase):
    def test_a_restaurant_takes_an_order(self):
        response = self.place_order()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['status'], Order.Status.PLACED)
        self.assertEqual(len(response.data['items']), 2)

    def test_a_lounge_refuses_with_a_reason(self):
        MenuItem.objects.create(
            establishment=self.lounge,
            name='Menthe',
            category=MenuItem.Category.CHICHA_FLAVOR,
            price=Decimal('50000.00'),
        )
        response = self.client.post(
            reverse('order-create'),
            {
                'establishment': self.lounge.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'pickup_time': self.pickup_time().isoformat(),
                'items': [
                    {
                        'menu_item': self.lounge.menu_items.first().pk,
                        'quantity': 1,
                    }
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        # A reason a customer can act on, not just a rejection.
        self.assertIn('only restaurants', str(response.data['establishment']))
        self.assertEqual(Order.objects.count(), 0)

    def test_the_total_comes_from_the_menu_not_the_client(self):
        response = self.place_order()

        # 2 x 75000 + 1 x 20000
        self.assertEqual(Decimal(response.data['total']), Decimal('170000.00'))

    def test_a_client_cannot_name_its_own_price(self):
        response = self.client.post(
            reverse('order-create'),
            {
                'establishment': self.restaurant.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'pickup_time': self.pickup_time().isoformat(),
                'items': [
                    {
                        'menu_item': self.poulet.pk,
                        'quantity': 1,
                        'unit_price_at_order': '1.00',
                    }
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Decimal(response.data['total']), Decimal('75000.00'))

    def test_a_standalone_pickup_has_no_reservation(self):
        response = self.place_order()

        self.assertIsNone(response.data['reservation'])
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_an_order_can_be_tied_to_a_booking(self):
        space = Space.objects.create(
            establishment=self.restaurant, name='Table 4', capacity=4
        )
        reservation = Reservation.objects.create(
            space=space,
            customer_name='Mariama Diallo',
            customer_phone='+224620000000',
            datetime=self.pickup_time(),
            party_size=2,
        )

        response = self.place_order(
            reservation_reference=str(reservation.reference)
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['reservation'], reservation.pk)

    def test_a_booking_at_another_venue_is_refused(self):
        other = Establishment.objects.create(
            name='Elsewhere',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre',
        )
        space = Space.objects.create(
            establishment=other, name='Table 1', capacity=2
        )
        reservation = Reservation.objects.create(
            space=space,
            customer_name='Mariama',
            customer_phone='+224620000000',
            datetime=self.pickup_time(),
            party_size=2,
        )

        response = self.place_order(
            reservation_reference=str(reservation.reference)
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_empty_cart_is_refused(self):
        response = self.client.post(
            reverse('order-create'),
            {
                'establishment': self.restaurant.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'pickup_time': self.pickup_time().isoformat(),
                'items': [],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_sold_out_dish_is_refused(self):
        self.poulet.is_available = False
        self.poulet.save(update_fields=['is_available'])

        response = self.place_order()

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('sold out', str(response.data['items']))

    def test_another_venues_dish_cannot_be_ordered(self):
        theirs = MenuItem.objects.create(
            establishment=self.lounge,
            name='Menthe',
            category=MenuItem.Category.CHICHA_FLAVOR,
            price=Decimal('50000.00'),
        )
        response = self.client.post(
            reverse('order-create'),
            {
                'establishment': self.restaurant.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'pickup_time': self.pickup_time().isoformat(),
                'items': [{'menu_item': theirs.pk, 'quantity': 1}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_pickup_time_in_the_past_is_refused(self):
        response = self.client.post(
            reverse('order-create'),
            {
                'establishment': self.restaurant.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'pickup_time': (
                    timezone.now() - timedelta(hours=1)
                ).isoformat(),
                'items': [{'menu_item': self.poulet.pk, 'quantity': 1}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class PriceSnapshotTests(OrderTestCase):
    def test_a_later_price_rise_does_not_change_what_is_owed(self):
        response = self.place_order()
        order = Order.objects.get(pk=response.data['id'])
        before = order.total

        # The merchant puts the chicken up by a third that afternoon.
        self.poulet.price = Decimal('100000.00')
        self.poulet.save(update_fields=['price'])

        order.refresh_from_db()
        self.assertEqual(order.total, before)
        self.assertEqual(order.total, Decimal('170000.00'))

        line = order.items.get(menu_item=self.poulet)
        self.assertEqual(line.unit_price_at_order, Decimal('75000.00'))

    def test_the_api_reads_back_the_snapshot_too(self):
        placed = self.place_order()
        reference = placed.data['reference']

        self.poulet.price = Decimal('100000.00')
        self.poulet.save(update_fields=['price'])

        response = self.client.get(
            reverse('order-by-reference', args=[reference])
        )

        self.assertEqual(Decimal(response.data['total']), Decimal('170000.00'))

    def test_deleting_the_dish_is_refused_rather_than_erasing_the_record(self):
        self.place_order()

        # PROTECT: what somebody bought is not the menu's to delete. Naming the
        # exception matters — a blind assertRaises would also pass if the
        # delete failed for some unrelated reason.
        with self.assertRaises(ProtectedError):
            self.poulet.delete()

        self.assertTrue(MenuItem.objects.filter(pk=self.poulet.pk).exists())


class PaymentGateTests(OrderTestCase):
    """Cash is worked on trust; mobile money is not."""

    def advance(self, order, to):
        return self.client.post(
            reverse('merchant-order-status', args=[order.pk]),
            {'status': to},
            format='json',
        )

    def test_a_cash_order_moves_through_the_kitchen_freely(self):
        placed = self.place_order(provider='cash_on_arrival')
        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.owner)

        preparing = self.advance(order, Order.Status.PREPARING)
        self.assertEqual(preparing.status_code, status.HTTP_200_OK)

        order.refresh_from_db()
        ready = self.advance(order, Order.Status.READY)
        self.assertEqual(ready.status_code, status.HTTP_200_OK)
        self.assertEqual(ready.data['status'], Order.Status.READY)

    def test_no_payment_row_is_written_for_cash(self):
        placed = self.place_order(provider='cash_on_arrival')

        self.assertEqual(
            Payment.objects.filter(order_id=placed.data['id']).count(), 0
        )

    def test_an_unpaid_mobile_money_order_cannot_be_started(self):
        with override_settings(PAYMENT_PROVIDERS=STUCK):
            placed = self.place_order(provider='orange_money')

        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.owner)

        with override_settings(PAYMENT_PROVIDERS=STUCK):
            response = self.advance(order, Order.Status.PREPARING)

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('payment is', response.data['detail'])

        order.refresh_from_db()
        self.assertEqual(order.status, Order.Status.PLACED)

    def test_an_unpaid_mobile_money_order_cannot_be_marked_ready(self):
        # Straight to ready, the jump a client might try to sneak through.
        with override_settings(PAYMENT_PROVIDERS=STUCK):
            placed = self.place_order(provider='orange_money')

        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.owner)

        with override_settings(PAYMENT_PROVIDERS=STUCK):
            response = self.advance(order, Order.Status.READY)

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        order.refresh_from_db()
        self.assertEqual(order.status, Order.Status.PLACED)

    def test_a_paid_mobile_money_order_moves_normally(self):
        placed = self.place_order(provider='orange_money')
        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.owner)

        response = self.advance(order, Order.Status.PREPARING)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_an_unpaid_order_can_still_be_cancelled(self):
        with override_settings(PAYMENT_PROVIDERS=STUCK):
            placed = self.place_order(provider='orange_money')

        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.owner)

        with override_settings(PAYMENT_PROVIDERS=STUCK):
            response = self.advance(order, Order.Status.CANCELLED)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], Order.Status.CANCELLED)

    def test_the_amount_charged_is_the_order_total_not_a_deposit(self):
        placed = self.place_order(provider='orange_money')

        payment = Payment.objects.get(order_id=placed.data['id'])
        self.assertEqual(payment.amount, Decimal('170000.00'))

    def test_can_advance_tells_the_app_what_the_server_would_do(self):
        with override_settings(PAYMENT_PROVIDERS=STUCK):
            placed = self.place_order(provider='orange_money')

        self.assertFalse(placed.data['can_advance'])

        paid = self.place_order(provider='orange_money')
        self.assertTrue(paid.data['can_advance'])


class KitchenQueueTests(OrderTestCase):
    def test_the_queue_lists_todays_orders(self):
        placed = self.place_order()

        # Pinned to midday rather than left at "two hours from now". The
        # endpoint filters on the local date, and a test run after 22:00 was
        # putting the pickup into tomorrow and finding an empty queue — the
        # assertion was right and the fixture was quietly time-dependent.
        midday = timezone.localtime(timezone.now()).replace(
            hour=12, minute=0, second=0, microsecond=0
        )
        Order.objects.filter(pk=placed.data['id']).update(pickup_time=midday)

        self.authenticate(self.owner)
        response = self.client.get(
            reverse('merchant-orders'), {'establishment': self.restaurant.pk}
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['results']), 1)

    def test_the_queue_is_todays_only(self):
        placed = self.place_order()
        Order.objects.filter(pk=placed.data['id']).update(
            pickup_time=timezone.now() + timedelta(days=2)
        )
        self.authenticate(self.owner)

        response = self.client.get(
            reverse('merchant-orders'), {'establishment': self.restaurant.pk}
        )

        # A kitchen screen showing next Tuesday's tickets is worse than useless.
        self.assertEqual(len(response.data['results']), 0)

    def test_it_can_be_filtered_by_status(self):
        self.place_order()
        self.authenticate(self.owner)

        response = self.client.get(
            reverse('merchant-orders'),
            {'establishment': self.restaurant.pk, 'status': 'ready'},
        )

        self.assertEqual(len(response.data['results']), 0)

    def test_a_venue_must_be_named(self):
        self.authenticate(self.owner)

        response = self.client.get(reverse('merchant-orders'))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_non_member_gets_404_not_403(self):
        outsider = User.objects.create_user('outsider', password='x')
        self.place_order()
        self.authenticate(outsider)

        response = self.client.get(
            reverse('merchant-orders'), {'establishment': self.restaurant.pk}
        )

        # Confirming the venue exists tells an outsider more than they need.
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_signing_out_closes_the_queue(self):
        self.place_order()

        response = self.client.get(
            reverse('merchant-orders'), {'establishment': self.restaurant.pk}
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_the_kitchen_path_cannot_be_skipped(self):
        placed = self.place_order()
        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.owner)

        response = self.client.post(
            reverse('merchant-order-status', args=[order.pk]),
            {'status': Order.Status.READY},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('not', response.data['detail'])

    def test_a_completed_order_cannot_be_reopened(self):
        placed = self.place_order()
        order = Order.objects.get(pk=placed.data['id'])
        order.status = Order.Status.COMPLETED
        order.save(update_fields=['status'])
        self.authenticate(self.owner)

        response = self.client.post(
            reverse('merchant-order-status', args=[order.pk]),
            {'status': Order.Status.PREPARING},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_an_invented_status_is_refused(self):
        placed = self.place_order()
        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.owner)

        response = self.client.post(
            reverse('merchant-order-status', args=[order.pk]),
            {'status': 'delivered'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class StaffRoleTests(OrderTestCase):
    """Working the queue is operations; editing the menu is not."""

    def test_staff_can_see_the_queue(self):
        self.place_order()
        self.authenticate(self.staff)

        response = self.client.get(
            reverse('merchant-orders'), {'establishment': self.restaurant.pk}
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_staff_can_move_an_order_along(self):
        placed = self.place_order()
        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.staff)

        response = self.client.post(
            reverse('merchant-order-status', args=[order.pk]),
            {'status': Order.Status.PREPARING},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_staff_still_cannot_edit_the_menu(self):
        self.authenticate(self.staff)

        response = self.client.post(
            reverse('merchant-menu', args=[self.restaurant.pk]),
            {
                'name': 'Riz gras',
                'category': 'food',
                'price': '40000.00',
            },
            format='json',
        )

        # Running the floor and changing what is sold are different rights.
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class CustomerTrackingTests(OrderTestCase):
    def test_an_order_is_followed_by_reference(self):
        placed = self.place_order()

        response = self.client.get(
            reverse('order-by-reference', args=[placed.data['reference']])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], Order.Status.PLACED)

    def test_the_sequential_id_is_not_a_key(self):
        placed = self.place_order()

        response = self.client.get(f'/api/orders/ref/{placed.data["id"]}/')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_an_unknown_reference_is_a_404(self):
        response = self.client.get(
            reverse(
                'order-by-reference',
                args=['11111111-2222-3333-4444-555555555555'],
            )
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_tracking_shows_the_kitchen_moving(self):
        placed = self.place_order()
        order = Order.objects.get(pk=placed.data['id'])
        self.authenticate(self.owner)
        self.client.post(
            reverse('merchant-order-status', args=[order.pk]),
            {'status': Order.Status.PREPARING},
            format='json',
        )

        self.client.credentials()
        response = self.client.get(
            reverse('order-by-reference', args=[placed.data['reference']])
        )

        self.assertEqual(response.data['status'], Order.Status.PREPARING)
        self.assertEqual(response.data['status_display'], 'Preparing')
