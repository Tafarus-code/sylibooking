"""The dishes feed — a shop window, not a dump of every menu.

The rules worth holding: only what a venue chose to feature, never anything
sold out, and each item carrying enough of its venue that a tap can land on
the right screen without a second request.
"""

from decimal import Decimal

from django.core.cache import cache
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from establishments.models import Establishment, MenuItem


class FeaturedItemsTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)

        self.restaurant = Establishment.objects.create(
            name='Le Baobab Doré',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Kaloum',
        )
        self.lounge = Establishment.objects.create(
            name='Chicha LaParisienne',
            type=Establishment.Type.LOUNGE,
            city='Labé',
            address='Kipé',
        )

    def item(self, establishment=None, **kwargs):
        defaults = {
            'establishment': establishment or self.restaurant,
            'name': 'Poulet yassa',
            'category': MenuItem.Category.FOOD,
            'price': Decimal('45000.00'),
            'is_featured': True,
        }
        return MenuItem.objects.create(**{**defaults, **kwargs})

    def get(self, **params):
        return self.client.get(reverse('featured-items'), params)

    def names(self, response):
        return [row['name'] for row in response.data['results']]

    def test_a_featured_dish_is_listed(self):
        self.item()

        response = self.get()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.names(response), ['Poulet yassa'])

    def test_an_ordinary_menu_item_is_not(self):
        """Otherwise the feed is the whole platform's menu, which is a
        spreadsheet rather than a shop window."""
        self.item(is_featured=False)

        self.assertEqual(self.names(self.get()), [])

    def test_a_sold_out_dish_is_not_shown(self):
        """A featured dish nobody can order is a wasted tap."""
        self.item(is_available=False)

        self.assertEqual(self.names(self.get()), [])

    def test_it_carries_the_venue_it_belongs_to(self):
        """So tapping one can open that venue under its own branding without
        a second round trip to find out whose dish it was."""
        self.item()

        row = self.get().data['results'][0]

        self.assertEqual(row['establishment'], self.restaurant.pk)
        self.assertEqual(row['establishment_name'], 'Le Baobab Doré')
        self.assertEqual(row['establishment_type'], 'restaurant')
        self.assertEqual(row['city'], 'Conakry')

    def test_the_price_comes_through_for_the_mono_face(self):
        self.item()

        self.assertEqual(self.get().data['results'][0]['price'], '45000.00')

    def test_a_dish_with_no_photo_says_so_rather_than_breaking(self):
        """Most items will have none, especially at first."""
        self.item()

        self.assertIsNone(self.get().data['results'][0]['image'])

    def test_it_can_be_narrowed_to_one_city(self):
        self.item()
        self.item(establishment=self.lounge, name='Chicha pomme')

        self.assertEqual(self.names(self.get(city='Labé')), ['Chicha pomme'])

    def test_and_to_one_kind_of_venue(self):
        self.item()
        self.item(establishment=self.lounge, name='Chicha pomme')

        self.assertEqual(
            self.names(self.get(type='lounge')), ['Chicha pomme']
        )

    def test_it_needs_no_account(self):
        """Discovery is the one surface that must work before anyone signs
        up — the whole app does."""
        self.item()

        self.assertEqual(self.get().status_code, status.HTTP_200_OK)

    def test_it_is_paginated_like_the_rest_of_the_catalogue(self):
        self.item()

        self.assertIn('count', self.get().data)
        self.assertIn('next', self.get().data)
