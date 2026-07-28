"""Hours and menu as the customer app receives them."""

from datetime import time
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from rest_framework import status

from establishments.models import Establishment, MenuItem, OpeningHours


class HoursAndMenuApiTestBase(TestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )

    def set_hours(self, day, opens=None, closes=None, is_closed=False):
        return OpeningHours.objects.create(
            establishment=self.establishment,
            day_of_week=day,
            is_closed=is_closed,
            opens=None if opens is None else time(*opens),
            closes=None if closes is None else time(*closes),
        )

    def add_item(self, name, category, price='25000', available=True):
        return MenuItem.objects.create(
            establishment=self.establishment,
            name=name,
            category=category,
            price=Decimal(price),
            is_available=available,
        )

    def detail(self):
        response = self.client.get(
            reverse('establishment-detail', args=[self.establishment.pk])
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data


class HoursInDetailTests(HoursAndMenuApiTestBase):
    def test_all_seven_days_are_returned(self):
        self.set_hours(OpeningHours.Day.FRIDAY, (18, 0), (2, 0))

        hours = self.detail()['hours']

        self.assertEqual(len(hours), 7)
        self.assertEqual([row['day_of_week'] for row in hours], list(range(7)))

    def test_days_the_merchant_never_set_come_back_closed(self):
        self.set_hours(OpeningHours.Day.FRIDAY, (18, 0), (2, 0))

        hours = self.detail()['hours']

        self.assertTrue(hours[OpeningHours.Day.MONDAY]['is_closed'])
        self.assertFalse(hours[OpeningHours.Day.FRIDAY]['is_closed'])

    def test_each_day_is_labelled(self):
        self.set_hours(OpeningHours.Day.MONDAY, (12, 0), (23, 0))

        hours = self.detail()['hours']

        self.assertEqual(hours[0]['day_display'], 'Monday')
        self.assertEqual(hours[6]['day_display'], 'Sunday')

    def test_overnight_days_are_flagged(self):
        self.set_hours(OpeningHours.Day.MONDAY, (18, 0), (2, 0))
        self.set_hours(OpeningHours.Day.TUESDAY, (12, 0), (23, 0))

        hours = self.detail()['hours']

        self.assertTrue(hours[OpeningHours.Day.MONDAY]['runs_past_midnight'])
        self.assertFalse(hours[OpeningHours.Day.TUESDAY]['runs_past_midnight'])

    def test_is_open_now_and_closes_at_are_present(self):
        self.set_hours(OpeningHours.Day.MONDAY, (12, 0), (23, 0))

        data = self.detail()

        self.assertIn('is_open_now', data)
        self.assertIn('closes_at', data)

    def test_an_establishment_with_no_hours_reports_closed(self):
        data = self.detail()

        self.assertFalse(data['is_open_now'])
        self.assertIsNone(data['closes_at'])
        self.assertIsNone(data['today'])
        # Still seven rows, so the app renders a full week.
        self.assertEqual(len(data['hours']), 7)


class MenuInDetailTests(HoursAndMenuApiTestBase):
    def test_items_are_grouped_by_category(self):
        self.add_item('Poulet braisé', MenuItem.Category.FOOD)
        self.add_item('Jus de gingembre', MenuItem.Category.DRINK)
        self.add_item('Menthe', MenuItem.Category.CHICHA_FLAVOR)

        menu = self.detail()['menu']

        self.assertEqual(
            [group['category'] for group in menu],
            ['food', 'drink', 'chicha_flavor'],
        )

    def test_each_group_is_labelled(self):
        self.add_item('Menthe', MenuItem.Category.CHICHA_FLAVOR)

        menu = self.detail()['menu']

        self.assertEqual(menu[0]['category_display'], 'Chicha flavour')

    def test_prices_are_included(self):
        self.add_item('Poulet braisé', MenuItem.Category.FOOD, price='75000')

        item = self.detail()['menu'][0]['items'][0]

        self.assertEqual(Decimal(item['price']), Decimal('75000'))
        self.assertEqual(item['name'], 'Poulet braisé')

    def test_unavailable_items_are_excluded(self):
        self.add_item('Poulet braisé', MenuItem.Category.FOOD)
        self.add_item('Poisson', MenuItem.Category.FOOD, available=False)

        items = self.detail()['menu'][0]['items']

        self.assertEqual([item['name'] for item in items], ['Poulet braisé'])

    def test_a_category_with_only_unavailable_items_is_dropped(self):
        """Otherwise the app renders a heading with nothing under it."""
        self.add_item('Poulet braisé', MenuItem.Category.FOOD)
        self.add_item('Coca', MenuItem.Category.DRINK, available=False)

        menu = self.detail()['menu']

        self.assertEqual([group['category'] for group in menu], ['food'])

    def test_an_establishment_with_no_menu_returns_an_empty_list(self):
        """Many pilot merchants will not have filled this in."""
        self.assertEqual(self.detail()['menu'], [])

    def test_an_establishment_with_only_unavailable_items_returns_empty(self):
        self.add_item('Poulet braisé', MenuItem.Category.FOOD, available=False)

        self.assertEqual(self.detail()['menu'], [])


class BrowseListTests(HoursAndMenuApiTestBase):
    def test_the_list_carries_an_open_indicator(self):
        self.set_hours(OpeningHours.Day.MONDAY, (12, 0), (23, 0))

        response = self.client.get(reverse('establishment-list'))
        row = response.data['results'][0]

        self.assertIn('is_open_now', row)
        self.assertIn('closes_at', row)

    def test_a_venue_with_no_hours_shows_as_closed_in_the_list(self):
        response = self.client.get(reverse('establishment-list'))

        self.assertFalse(response.data['results'][0]['is_open_now'])

    def test_listing_does_not_query_hours_per_establishment(self):
        for index in range(8):
            other = Establishment.objects.create(
                name=f'Venue {index}',
                type=Establishment.Type.LOUNGE,
                city='Conakry',
                address='Somewhere',
            )
            OpeningHours.objects.create(
                establishment=other,
                day_of_week=OpeningHours.Day.MONDAY,
                opens=time(12, 0),
                closes=time(23, 0),
            )

        # count, the page itself, and one prefetch for hours.
        with self.assertNumQueries(3):
            self.client.get(reverse('establishment-list'))
