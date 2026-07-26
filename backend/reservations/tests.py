from django.db.models import ProtectedError
from django.test import TestCase
from django.utils import timezone

from establishments.models import Establishment, Space

from .models import Reservation


class ReservationModelTests(TestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )
        self.space = Space.objects.create(
            establishment=self.establishment,
            name='VIP Room 1',
            type=Space.Type.VIP_ROOM,
            capacity=10,
        )
        self.when = timezone.now() + timezone.timedelta(days=1)

    def _reservation(self, **overrides):
        fields = {
            'space': self.space,
            'customer_name': 'Mariama Diallo',
            'customer_phone': '+224 620 00 00 00',
            'datetime': self.when,
            'party_size': 4,
        }
        fields.update(overrides)
        return Reservation.objects.create(**fields)

    def test_new_reservations_start_pending(self):
        """The merchant has to confirm; nothing is booked by default."""
        self.assertEqual(self._reservation().status, Reservation.Status.PENDING)

    def test_str_includes_customer_space_and_status(self):
        reservation = self._reservation()
        self.assertIn('Mariama Diallo', str(reservation))
        self.assertIn('VIP Room 1', str(reservation))
        self.assertIn('Pending', str(reservation))

    def test_created_at_is_set_automatically(self):
        self.assertIsNotNone(self._reservation().created_at)

    def test_reservations_are_reachable_from_the_space(self):
        reservation = self._reservation()
        self.assertIn(reservation, self.space.reservations.all())

    def test_ordered_most_recent_first(self):
        earlier = self._reservation(datetime=self.when)
        later = self._reservation(datetime=self.when + timezone.timedelta(hours=2))
        self.assertEqual(list(Reservation.objects.all()), [later, earlier])

    def test_space_with_reservations_cannot_be_deleted(self):
        """Deleting a table must not silently erase its booking history."""
        self._reservation()
        with self.assertRaises(ProtectedError):
            self.space.delete()