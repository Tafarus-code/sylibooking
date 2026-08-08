"""An order rung up at the counter, for somebody standing there.

`Order.reservation` has been nullable since ordering was built, precisely so
an order could stand alone. The model anticipated this and only the way in
was missing — a merchant could work a queue of orders customers had placed
themselves, and could not add the one in front of them.

What these mostly guard is that a walk-in is *not* a customer order with
blanks in it: no phone, no account, no pickup time in the future, and it goes
straight into the same kitchen queue as everything else.
"""

from datetime import datetime, time, timedelta
from decimal import Decimal

from django.contrib.auth.models import User
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
from reservations.models import Reservation


class WalkInTestBase(APITestCase):
    def setUp(self):
        self.venue = Establishment.objects.create(
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
            establishment=self.venue,
            name='Poulet braisé',
            category=MenuItem.Category.FOOD,
            price=Decimal('75000.00'),
        )
        self.jus = MenuItem.objects.create(
            establishment=self.venue,
            name='Jus de gingembre',
            category=MenuItem.Category.DRINK,
            price=Decimal('15000.00'),
        )
        self.sold_out = MenuItem.objects.create(
            establishment=self.venue,
            name='Capitaine grillé',
            category=MenuItem.Category.FOOD,
            price=Decimal('90000.00'),
            is_available=False,
        )

        self.owner = self.member('amadou', MerchantMembership.Role.OWNER)
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

    def url(self, establishment=None):
        return reverse(
            'merchant-walk-in-order', args=[(establishment or self.venue).pk]
        )

    def ring_up(self, items=None, **extra):
        payload = {
            'items': items or [{'menu_item': self.poulet.pk, 'quantity': 1}],
            **extra,
        }
        return self.client.post(self.url(), payload, format='json')


class RingingUpTests(WalkInTestBase):
    def test_staff_can_ring_one_up(self):
        """Floor work. Routing it through a manager is how a queue ends up on
        a paper pad instead."""
        self.authenticate(self.floor)

        response = self.ring_up()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Order.objects.count(), 1)

    def test_an_owner_can_too(self):
        self.authenticate(self.owner)

        self.assertEqual(
            self.ring_up().status_code, status.HTTP_201_CREATED
        )

    def test_a_non_member_is_told_nothing(self):
        self.authenticate(self.outsider)

        response = self.ring_up()

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(Order.objects.exists())

    def test_a_signed_out_caller_is_refused(self):
        response = self.ring_up()

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_it_belongs_to_no_booking(self):
        """The whole point: an order that stands alone."""
        self.authenticate(self.floor)

        self.ring_up()

        self.assertIsNone(Order.objects.get().reservation)

    def test_a_walk_in_needs_no_phone_number(self):
        """Nobody's business if the customer is waiting in the room."""
        self.authenticate(self.floor)

        response = self.ring_up()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Order.objects.get().customer_phone, '')

    def test_a_walk_in_needs_no_name_either(self):
        self.authenticate(self.floor)

        response = self.ring_up()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        # Something has to be called out when the food is up.
        self.assertTrue(Order.objects.get().customer_name)

    def test_a_name_is_kept_when_one_is_given(self):
        self.authenticate(self.floor)

        self.ring_up(customer_name='Mariama')

        self.assertEqual(Order.objects.get().customer_name, 'Mariama')

    def test_collection_is_now_unless_told_otherwise(self):
        """Making a merchant enter a time to sell a coffee is the friction
        that gets a system abandoned."""
        self.authenticate(self.floor)
        before = timezone.now()

        self.ring_up()

        order = Order.objects.get()
        self.assertGreaterEqual(order.pickup_time, before)
        self.assertLessEqual(
            order.pickup_time, timezone.now() + timedelta(seconds=5)
        )

    def test_a_later_collection_can_be_asked_for(self):
        self.authenticate(self.floor)
        later = timezone.now() + timedelta(hours=2)

        self.ring_up(pickup_time=later.isoformat())

        self.assertAlmostEqual(
            Order.objects.get().pickup_time, later, delta=timedelta(seconds=2)
        )


class KitchenQueueTests(WalkInTestBase):
    def test_it_goes_straight_into_the_kitchen(self):
        """Already taken, nothing to wait on, nobody to confirm it."""
        self.authenticate(self.floor)

        self.ring_up()

        self.assertEqual(Order.objects.get().status, Order.Status.PLACED)

    def test_it_appears_in_the_same_queue_as_a_customer_order(self):
        self.authenticate(self.floor)
        # Pinned to midday rather than now + an hour: the queue is filtered
        # to today, and near midnight "in an hour" is tomorrow.
        midday = timezone.localtime(timezone.now()).replace(
            hour=12, minute=0, second=0, microsecond=0
        )
        Order.objects.create(
            establishment=self.venue,
            customer_name='Mariama',
            customer_phone='+224620000000',
            pickup_time=midday,
        )

        self.ring_up(customer_name='Counter')

        response = self.client.get(
            reverse('merchant-orders'), {'establishment': self.venue.pk}
        )

        names = {o['customer_name'] for o in response.data['results']}
        self.assertEqual(names, {'Mariama', 'Counter'})

    def test_it_can_be_worked_through_the_stages_like_any_other(self):
        self.authenticate(self.floor)
        created = self.ring_up()
        order_id = created.data['id']

        response = self.client.post(
            reverse('merchant-order-status', args=[order_id]),
            {'status': 'preparing'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class MoneyTests(WalkInTestBase):
    def test_no_payment_row_is_written(self):
        """Cash in the room. There is no prompt to push and nothing to wait
        for — exactly as cash on pickup already behaves."""
        self.authenticate(self.floor)

        self.ring_up()

        self.assertFalse(Payment.objects.exists())

    def test_the_total_comes_from_the_menu_not_the_caller(self):
        """What a dish costs is the menu's to say."""
        self.authenticate(self.floor)

        self.ring_up(
            items=[
                {'menu_item': self.poulet.pk, 'quantity': 2},
                {'menu_item': self.jus.pk, 'quantity': 1},
            ],
        )

        self.assertEqual(Order.objects.get().total, Decimal('165000.00'))

    def test_a_price_in_the_request_is_ignored(self):
        self.authenticate(self.floor)

        self.ring_up(
            items=[
                {
                    'menu_item': self.poulet.pk,
                    'quantity': 1,
                    'unit_price_at_order': '1.00',
                }
            ],
        )

        self.assertEqual(Order.objects.get().total, Decimal('75000.00'))


class ValidationTests(WalkInTestBase):
    def test_an_empty_order_is_refused(self):
        self.authenticate(self.floor)

        response = self.client.post(self.url(), {'items': []}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_sold_out_dish_is_refused(self):
        """The same rule the customer's cart follows."""
        self.authenticate(self.floor)

        response = self.ring_up(
            items=[{'menu_item': self.sold_out.pk, 'quantity': 1}]
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(Order.objects.exists())

    def test_another_venues_dish_is_refused(self):
        other_item = MenuItem.objects.create(
            establishment=self.lounge,
            name='Menthe',
            category=MenuItem.Category.CHICHA_FLAVOR,
            price=Decimal('50000.00'),
        )
        self.authenticate(self.floor)

        response = self.ring_up(
            items=[{'menu_item': other_item.pk, 'quantity': 1}]
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_the_same_dish_twice_is_refused(self):
        self.authenticate(self.floor)

        response = self.ring_up(
            items=[
                {'menu_item': self.poulet.pk, 'quantity': 1},
                {'menu_item': self.poulet.pk, 'quantity': 2},
            ]
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_lounge_still_does_not_take_orders(self):
        """The same restaurant-only rule the customer side follows. Whether a
        lounge *should* be able to ring up chicha at the counter is a product
        question; this keeps the two sides agreeing until it is answered.
        """
        owner = self.member(
            'baobab', MerchantMembership.Role.OWNER, establishment=self.lounge
        )
        self.authenticate(owner)
        item = MenuItem.objects.create(
            establishment=self.lounge,
            name='Menthe',
            category=MenuItem.Category.CHICHA_FLAVOR,
            price=Decimal('50000.00'),
        )

        response = self.client.post(
            self.url(establishment=self.lounge),
            {'items': [{'menu_item': item.pk, 'quantity': 1}]},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('establishment', response.data)

    def test_a_walk_in_cannot_be_attached_to_a_booking(self):
        """There is no field for it, and a counter order is not a pre-order."""
        table = Space.objects.create(
            establishment=self.venue, name='Table 1', capacity=4
        )
        booking = Reservation.objects.create(
            space=table,
            customer_name='Mariama',
            customer_phone='+224620000000',
            datetime=timezone.now() + timedelta(hours=1),
            party_size=2,
        )
        self.authenticate(self.floor)

        self.ring_up(reservation_reference=str(booking.reference))

        self.assertIsNone(Order.objects.get().reservation)


class QueuePaginationTests(WalkInTestBase):
    """The kitchen queue at real volume.

    It used to return every ticket for the day in one response. Fine at
    twenty; a busy Saturday is not twenty.
    """

    def orders(self, howMany):
        # Pinned to midday, not "half an hour from now". The queue shows
        # today's tickets, and a pickup half an hour after 23:55 in Conakry
        # is tomorrow's — so this whole class failed for the last thirty
        # minutes of every day and passed for the other twenty-three and a
        # half hours.
        today = timezone.localdate()
        pickup = timezone.make_aware(
            datetime.combine(today, time(12, 0)),
            timezone.get_current_timezone(),
        )
        Order.objects.bulk_create(
            [
                Order(
                    establishment=self.venue,
                    customer_name=f'Customer {i}',
                    customer_phone='',
                    pickup_time=pickup,
                )
                for i in range(howMany)
            ]
        )

    def ask(self, **params):
        return self.client.get(
            reverse('merchant-orders'),
            {'establishment': self.venue.pk, **params},
        )

    def test_the_queue_comes_back_paged(self):
        self.orders(120)
        self.authenticate(self.floor)

        response = self.ask()

        self.assertEqual(response.data['count'], 120)
        self.assertEqual(len(response.data['results']), 50)
        self.assertIsNotNone(response.data['next'])

    def test_the_next_page_carries_on(self):
        self.orders(120)
        self.authenticate(self.floor)

        response = self.ask(page=2)

        self.assertEqual(len(response.data['results']), 50)

    def test_the_last_page_says_it_is_the_last(self):
        self.orders(120)
        self.authenticate(self.floor)

        response = self.ask(page=3)

        self.assertEqual(len(response.data['results']), 20)
        self.assertIsNone(response.data['next'])

    def test_a_quiet_venue_still_gets_one_page(self):
        """A change that only shows up under load must not change the quiet
        case."""
        self.orders(3)
        self.authenticate(self.floor)

        response = self.ask()

        self.assertEqual(len(response.data['results']), 3)
        self.assertIsNone(response.data['next'])

    def test_a_page_size_can_be_asked_for(self):
        self.orders(30)
        self.authenticate(self.floor)

        response = self.ask(page_size=10)

        self.assertEqual(len(response.data['results']), 10)

    def test_an_absurd_page_size_is_capped(self):
        """Otherwise page_size=100000 is a way to ask for the whole table."""
        self.orders(60)
        self.authenticate(self.floor)

        response = self.ask(page_size=100000)

        self.assertLessEqual(len(response.data['results']), 200)
