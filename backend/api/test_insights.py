"""What a venue learns about itself, and what it must never be told.

The arithmetic is checked against a fixture small enough to add up by hand,
because a analytics screen that is subtly wrong is worse than none: a merchant
acts on it, and nothing about the number itself says it is lying.
"""

from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from orders.models import Order, OrderItem
from rest_framework import status
from rest_framework.test import APITestCase

from establishments.models import Establishment, MenuItem, MerchantMembership, Space
from reservations.models import Reservation

User = get_user_model()


class InsightsTestBase(APITestCase):
    def setUp(self):
        self.venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Kaloum',
        )
        self.other = Establishment.objects.create(
            name='Chez Mariama',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Dixinn',
        )
        self.table = Space.objects.create(
            establishment=self.venue, name='Table 1', capacity=6
        )
        self.owner = User.objects.create_user('amadou', password='x' * 12)
        MerchantMembership.objects.create(
            user=self.owner,
            establishment=self.venue,
            role=MerchantMembership.Role.OWNER,
        )
        self.client.force_authenticate(self.owner)

    def url(self, establishment=None, **params):
        path = reverse(
            'merchant-insights', args=[(establishment or self.venue).pk]
        )
        if params:
            query = '&'.join(f'{k}={v}' for k, v in params.items())
            return f'{path}?{query}'
        return path

    def book(self, *, days_ago=1, hour=19, party=2, phone='+224620000001',
             status_=Reservation.Status.COMPLETED, space=None):
        when = (timezone.localtime() - timedelta(days=days_ago)).replace(
            hour=hour, minute=0, second=0, microsecond=0
        )
        return Reservation.objects.create(
            space=space or self.table,
            customer_name='Mariama Diallo',
            customer_phone=phone,
            datetime=when,
            party_size=party,
            status=status_,
        )


class CoversTests(InsightsTestBase):
    def test_covers_count_people_not_bookings(self):
        self.book(party=2)
        self.book(party=4, hour=20)

        covers = self.client.get(self.url()).data['covers']

        self.assertEqual(covers['total'], 6)
        self.assertEqual(covers['bookings'], 2)
        self.assertEqual(covers['average_party_size'], 3.0)

    def test_a_cancelled_booking_was_never_a_cover(self):
        self.book(party=4)
        self.book(party=100, status_=Reservation.Status.CANCELLED, hour=20)

        covers = self.client.get(self.url()).data['covers']

        self.assertEqual(covers['total'], 4)

    def test_a_missed_booking_is_not_a_cover_either(self):
        self.book(party=4)
        self.book(party=50, status_=Reservation.Status.NO_SHOW, hour=20)

        self.assertEqual(self.client.get(self.url()).data['covers']['total'], 4)

    def test_a_booking_still_ahead_is_not_counted(self):
        """Counts describe what happened, not what was promised."""
        self.book(party=4)
        self.book(days_ago=-3, party=40, status_=Reservation.Status.CONFIRMED)

        self.assertEqual(self.client.get(self.url()).data['covers']['total'], 4)

    def test_every_weekday_is_present_even_when_quiet(self):
        """A chart with Wednesday missing reads as a rendering bug."""
        self.book(party=2)

        by_weekday = self.client.get(self.url()).data['covers']['by_weekday']

        self.assertEqual(len(by_weekday), 7)
        self.assertEqual([row['weekday'] for row in by_weekday], list(range(7)))

    def test_covers_land_on_the_right_weekday(self):
        booking = self.book(days_ago=2, party=5)
        expected = timezone.localtime(booking.datetime).weekday()

        by_weekday = self.client.get(self.url()).data['covers']['by_weekday']

        self.assertEqual(by_weekday[expected]['covers'], 5)

    def test_average_party_size_is_null_with_nothing_to_average(self):
        covers = self.client.get(self.url()).data['covers']

        self.assertIsNone(covers['average_party_size'])
        self.assertEqual(covers['total'], 0)


class AttendanceTests(InsightsTestBase):
    def test_missed_and_cancelled_are_reported_apart(self):
        """**The distinction the section exists for.**

        A stranger who never came and a customer who telephoned are not the
        same event, and a merchant reading one number would learn to distrust
        the people who behaved well.
        """
        self.book(status_=Reservation.Status.COMPLETED)
        self.book(status_=Reservation.Status.NO_SHOW, hour=20)
        self.book(status_=Reservation.Status.CANCELLED, hour=21)
        self.book(status_=Reservation.Status.CANCELLED, hour=22)

        attendance = self.client.get(self.url()).data['attendance']

        self.assertEqual(attendance['missed'], 1)
        self.assertEqual(attendance['cancelled'], 2)
        self.assertEqual(attendance['total'], 4)
        self.assertEqual(attendance['missed_rate'], 0.25)
        self.assertEqual(attendance['cancelled_rate'], 0.5)

    def test_the_unfilled_rate_adds_them_up(self):
        self.book(status_=Reservation.Status.COMPLETED)
        self.book(status_=Reservation.Status.NO_SHOW, hour=20)
        self.book(status_=Reservation.Status.CANCELLED, hour=21)

        attendance = self.client.get(self.url()).data['attendance']

        self.assertAlmostEqual(attendance['unfilled_rate'], 0.6667, places=3)

    def test_rates_are_null_rather_than_zero_when_nothing_happened(self):
        """A venue with no bookings has no no-show rate. Reporting 0% would
        be reassuring and false."""
        attendance = self.client.get(self.url()).data['attendance']

        self.assertEqual(attendance['total'], 0)
        self.assertIsNone(attendance['missed_rate'])
        self.assertIsNone(attendance['cancelled_rate'])


class PeakHourTests(InsightsTestBase):
    def test_hours_carry_their_bookings_and_covers(self):
        self.book(hour=19, party=2)
        self.book(hour=19, party=4)
        self.book(hour=22, party=3)

        hours = self.client.get(self.url()).data['peak_hours']

        self.assertEqual(
            hours,
            [
                {'hour': 19, 'bookings': 2, 'covers': 6},
                {'hour': 22, 'bookings': 1, 'covers': 3},
            ],
        )

    def test_hours_with_nothing_in_them_are_left_out(self):
        """A lounge opening at 17:00 does not want two thirds of an empty
        chart it can never fill."""
        self.book(hour=21)

        hours = self.client.get(self.url()).data['peak_hours']

        self.assertEqual([row['hour'] for row in hours], [21])


class DishTests(InsightsTestBase):
    def setUp(self):
        super().setUp()
        self.cheap = MenuItem.objects.create(
            establishment=self.venue,
            name='Alloco',
            category=MenuItem.Category.FOOD,
            price=Decimal('20000.00'),
        )
        self.dear = MenuItem.objects.create(
            establishment=self.venue,
            name='Poisson braisé',
            category=MenuItem.Category.FOOD,
            price=Decimal('90000.00'),
        )

    def order(self, item, quantity, *, days_ago=1, status_=Order.Status.COMPLETED):
        order = Order.objects.create(
            establishment=self.venue,
            customer_name='Mariama',
            customer_phone='+224620000001',
            pickup_time=timezone.localtime() - timedelta(days=days_ago),
            status=status_,
        )
        OrderItem.objects.create(
            order=order,
            menu_item=item,
            quantity=quantity,
            unit_price_at_order=item.price,
        )
        return order

    def test_the_two_rankings_disagree_and_both_are_reported(self):
        """**Why there are two lists.**

        Ten portions of alloco at 20,000 outsell three whole fish at 90,000
        and earn less than them — 200,000 against 270,000. A venue told only
        one of those rankings is being told half of what it sells.
        """
        self.order(self.cheap, 10)
        self.order(self.dear, 3)

        dishes = self.client.get(self.url()).data['dishes']

        self.assertEqual(dishes['by_quantity'][0]['name'], 'Alloco')
        self.assertEqual(dishes['by_revenue'][0]['name'], 'Poisson braisé')

    def test_revenue_uses_the_price_that_was_charged(self):
        """Not the price on the menu today: what a dish earned last month is
        what it was sold for last month."""
        self.order(self.dear, 2)
        self.dear.price = Decimal('120000.00')
        self.dear.save()

        dishes = self.client.get(self.url()).data['dishes']

        self.assertEqual(dishes['by_revenue'][0]['revenue'], '180000.00')

    def test_a_cancelled_order_sold_nothing(self):
        self.order(self.cheap, 5, status_=Order.Status.CANCELLED)

        dishes = self.client.get(self.url()).data['dishes']

        self.assertEqual(dishes['by_quantity'], [])

    def test_money_travels_as_a_string(self):
        self.order(self.cheap, 3)

        revenue = self.client.get(self.url()).data['dishes']['by_revenue'][0]

        self.assertIsInstance(revenue['revenue'], str)
        self.assertEqual(revenue['revenue'], '60000.00')


class RepeatCustomerTests(InsightsTestBase):
    def test_a_first_visit_is_not_a_return(self):
        self.book(phone='+224620000001')

        repeat = self.client.get(self.url()).data['repeat_customers']

        self.assertEqual(repeat['returning_bookings'], 0)
        self.assertEqual(repeat['returning_rate'], 0.0)

    def test_the_second_booking_from_a_number_is_a_return(self):
        self.book(days_ago=5, phone='+224620000001')
        self.book(days_ago=1, phone='+224620000001', hour=20)

        repeat = self.client.get(self.url()).data['repeat_customers']

        self.assertEqual(repeat['bookings'], 2)
        self.assertEqual(repeat['returning_bookings'], 1)
        self.assertEqual(repeat['returning_customers'], 1)
        self.assertEqual(repeat['returning_rate'], 0.5)

    def test_a_regular_from_before_the_window_still_counts_as_returning(self):
        """**The window must not manufacture new customers.**

        Someone who has come monthly for a year is not a first-timer because
        the merchant chose to look at seven days.
        """
        self.book(days_ago=200, phone='+224620000009')
        self.book(days_ago=1, phone='+224620000009')

        repeat = self.client.get(self.url(days=7)).data['repeat_customers']

        self.assertEqual(repeat['bookings'], 1)
        self.assertEqual(repeat['returning_bookings'], 1)

    def test_identity_is_the_phone_number_not_an_account(self):
        """Accounts are optional and most customers never make one; counting
        only signed-in regulars would report loyalty as near zero."""
        self.book(days_ago=5, phone='+224620000002')
        self.book(days_ago=1, phone='+224620000002', hour=20)

        repeat = self.client.get(self.url()).data['repeat_customers']

        self.assertEqual(repeat['returning_customers'], 1)

    def test_a_booking_with_no_number_is_left_out(self):
        self.book(phone='')

        repeat = self.client.get(self.url()).data['repeat_customers']

        self.assertEqual(repeat['bookings'], 0)
        self.assertIsNone(repeat['returning_rate'])


class WindowTests(InsightsTestBase):
    def test_the_default_window_is_thirty_days(self):
        response = self.client.get(self.url())

        self.assertEqual(response.data['window']['days'], 30)

    def test_a_shorter_window_excludes_what_is_outside_it(self):
        self.book(days_ago=20, party=9)
        self.book(days_ago=2, party=3)

        covers = self.client.get(self.url(days=7)).data['covers']

        self.assertEqual(covers['total'], 3)

    def test_a_longer_window_includes_it(self):
        self.book(days_ago=20, party=9)
        self.book(days_ago=2, party=3)

        covers = self.client.get(self.url(days=30)).data['covers']

        self.assertEqual(covers['total'], 12)

    def test_an_unoffered_window_is_refused(self):
        """Not free-form: two merchants comparing 30 days against 28 are
        comparing nothing."""
        response = self.client.get(self.url(days=45))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_nonsense_is_refused_clearly(self):
        response = self.client.get(self.url(days='last-tuesday'))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class ScopingTests(InsightsTestBase):
    def test_another_venue_s_bookings_are_not_counted(self):
        other_table = Space.objects.create(
            establishment=self.other, name='Table 1', capacity=4
        )
        self.book(party=3)
        self.book(party=40, space=other_table, hour=20)

        covers = self.client.get(self.url()).data['covers']

        self.assertEqual(covers['total'], 3)

    def test_a_non_member_gets_404_not_403(self):
        """Matching the posture everywhere else: 403 would confirm the venue
        exists to somebody with no business knowing."""
        outsider = User.objects.create_user('stranger', password='x' * 12)
        self.client.force_authenticate(outsider)

        response = self.client.get(self.url())

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_staff_may_read_the_room_they_work(self):
        """Which night is busy is floor knowledge. The payments dashboard
        draws the same line."""
        member = User.objects.create_user('binta', password='x' * 12)
        MerchantMembership.objects.create(
            user=member,
            establishment=self.venue,
            role=MerchantMembership.Role.STAFF,
        )
        self.client.force_authenticate(member)

        response = self.client.get(self.url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_signing_in_is_required(self):
        self.client.force_authenticate(None)

        response = self.client.get(self.url())

        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )
