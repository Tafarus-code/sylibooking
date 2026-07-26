from django.db import IntegrityError, transaction
from django.test import TestCase

from .models import Establishment, Space


class EstablishmentModelTests(TestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )

    def test_str_includes_name_and_city(self):
        self.assertEqual(str(self.establishment), 'Le Petit Baobab (Conakry)')

    def test_geo_and_opening_hours_are_optional(self):
        """A merchant can register before knowing their exact coordinates."""
        self.assertIsNone(self.establishment.latitude)
        self.assertIsNone(self.establishment.longitude)
        self.assertEqual(self.establishment.opening_hours, '')

    def test_created_at_is_set_automatically(self):
        self.assertIsNotNone(self.establishment.created_at)


class SpaceModelTests(TestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre-ville, Labé',
        )
        self.space = Space.objects.create(
            establishment=self.establishment,
            name='Table 4',
            type=Space.Type.TABLE,
            capacity=6,
        )

    def test_str_includes_space_and_establishment(self):
        self.assertEqual(str(self.space), 'Table 4 — Chez Fatou')

    def test_defaults_to_table_type(self):
        space = Space.objects.create(
            establishment=self.establishment, name='Table 5', capacity=2
        )
        self.assertEqual(space.type, Space.Type.TABLE)

    def test_name_must_be_unique_within_an_establishment(self):
        """Two "Table 4"s in one venue would make the merchant view ambiguous."""
        with self.assertRaises(IntegrityError), transaction.atomic():
            Space.objects.create(
                establishment=self.establishment, name='Table 4', capacity=4
            )

    def test_same_name_allowed_in_a_different_establishment(self):
        other = Establishment.objects.create(
            name='Le Mirador',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Ratoma, Conakry',
        )
        space = Space.objects.create(establishment=other, name='Table 4', capacity=4)
        self.assertEqual(space.name, 'Table 4')

    def test_spaces_are_reachable_from_the_establishment(self):
        self.assertIn(self.space, self.establishment.spaces.all())

    def test_deleting_an_establishment_removes_its_spaces(self):
        self.establishment.delete()
        self.assertFalse(Space.objects.filter(pk=self.space.pk).exists())