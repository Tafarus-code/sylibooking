"""Exporting the books, and the characters that break a naive export.

The interesting tests here are not the happy ones. A venue called "Chez Sory,
Kaloum" and a customer who put a newline in their name both produce a file
that opens fine and is quietly wrong, and the only way to know is to read it
back with a parser rather than to look at it.
"""

import csv
from datetime import timedelta
from decimal import Decimal
from io import StringIO

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from establishments.models import Establishment, MerchantMembership, Space
from payments.models import Payment
from reservations.models import Reservation

User = get_user_model()


def parsed(response):
    """The file as a spreadsheet would read it, BOM stripped."""
    text = response.content.decode('utf-8-sig')
    return list(csv.reader(StringIO(text)))


class ExportTestBase(APITestCase):
    def setUp(self):
        self.venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.table = Space.objects.create(
            establishment=self.venue, name='Table 1', capacity=4
        )
        self.owner = User.objects.create_user('amadou', password='x' * 12)
        MerchantMembership.objects.create(
            user=self.owner,
            establishment=self.venue,
            role=MerchantMembership.Role.OWNER,
        )
        self.client.force_authenticate(self.owner)

    def url(self, **params):
        path = reverse('merchant-export', args=[self.venue.pk])
        if params:
            return f'{path}?' + '&'.join(f'{k}={v}' for k, v in params.items())
        return path

    def book(self, *, name='Mariama Diallo', days_ago=1, party=2, hour=19):
        when = (timezone.localtime() - timedelta(days=days_ago)).replace(
            hour=hour, minute=30, second=0, microsecond=0
        )
        return Reservation.objects.create(
            space=self.table,
            customer_name=name,
            customer_phone='+224620000001',
            datetime=when,
            party_size=party,
            status=Reservation.Status.COMPLETED,
        )


class BookingExportTests(ExportTestBase):
    def test_it_arrives_as_a_csv_file_with_a_name(self):
        response = self.client.get(self.url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('text/csv', response['Content-Type'])
        self.assertIn('attachment; filename=', response['Content-Disposition'])
        self.assertIn('bookings', response['Content-Disposition'])

    def test_a_booking_becomes_a_row(self):
        self.book(party=4)

        rows = parsed(self.client.get(self.url()))

        self.assertEqual(rows[0][0], 'reference')
        self.assertEqual(len(rows), 2)
        self.assertIn('Mariama Diallo', rows[1])
        self.assertIn('4', rows[1])
        self.assertIn('Table 1', rows[1])

    def test_a_comma_in_a_name_does_not_move_a_column(self):
        """**The test this file exists for.**

        "Chez Sory, Kaloum" written by joining commas produces a row one
        field longer than its header. The file still opens, every column
        after it is shifted, and nobody finds out until the totals disagree.
        """
        self.book(name='Sory, Kaloum')

        rows = parsed(self.client.get(self.url()))

        self.assertEqual(len(rows[1]), len(rows[0]))
        self.assertIn('Sory, Kaloum', rows[1])

    def test_a_quote_in_a_name_survives(self):
        self.book(name='Mariama "La Patronne" Diallo')

        rows = parsed(self.client.get(self.url()))

        self.assertEqual(len(rows[1]), len(rows[0]))
        self.assertIn('Mariama "La Patronne" Diallo', rows[1])

    def test_a_newline_in_a_name_stays_inside_its_field(self):
        # A parser reading this back must still see two rows, not three.
        self.book(name='Mariama\nDiallo')

        rows = parsed(self.client.get(self.url()))

        self.assertEqual(len(rows), 2)
        self.assertIn('Mariama\nDiallo', rows[1])

    def test_accents_survive_the_round_trip(self):
        self.book(name='Aïssatou Baldé')

        rows = parsed(self.client.get(self.url()))

        self.assertIn('Aïssatou Baldé', rows[1])

    def test_the_file_starts_with_a_byte_order_mark(self):
        """Excel reads a UTF-8 CSV as the system code page without one, and
        every accented name in the file arrives mangled."""
        response = self.client.get(self.url())

        self.assertTrue(response.content.startswith(b'\xef\xbb\xbf'))

    def test_a_range_with_nothing_in_it_is_a_header_and_no_rows(self):
        """Not an error, and not an empty file: an accountant opening it
        should see the columns and conclude there was no trade."""
        self.book(days_ago=200)

        rows = parsed(self.client.get(self.url()))

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][0], 'reference')


class PaymentExportTests(ExportTestBase):
    def test_payments_export_their_own_columns(self):
        booking = self.book()
        Payment.objects.create(
            reservation=booking,
            provider=Payment.Provider.ORANGE_MONEY,
            amount=Decimal('50000.00'),
            status=Payment.Status.COMPLETED,
            provider_reference='MOCK-1',
        )

        rows = parsed(self.client.get(self.url(kind='payments')))

        self.assertEqual(rows[0][0], 'created')
        self.assertIn('MOCK-1', rows[1])
        self.assertIn('50000.00', rows[1])

    def test_an_unknown_kind_is_refused(self):
        response = self.client.get(self.url(kind='everything'))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class ExportScopingTests(ExportTestBase):
    def test_another_venue_s_bookings_are_not_in_the_file(self):
        other = Establishment.objects.create(
            name='Chez Mariama',
            type=Establishment.Type.RESTAURANT,
            city='Conakry',
            address='Dixinn',
        )
        other_table = Space.objects.create(
            establishment=other, name='Table 9', capacity=4
        )
        Reservation.objects.create(
            space=other_table,
            customer_name='Somebody Else',
            customer_phone='+224620000002',
            datetime=timezone.localtime() - timedelta(days=1),
            party_size=2,
            status=Reservation.Status.COMPLETED,
        )
        self.book()

        rows = parsed(self.client.get(self.url()))

        self.assertEqual(len(rows), 2)
        self.assertNotIn('Somebody Else', rows[1])

    def test_staff_may_not_export_the_books(self):
        """They can read tonight's takings on the dashboard. Copying the
        whole ledger out is a different act."""
        member = User.objects.create_user('binta', password='x' * 12)
        MerchantMembership.objects.create(
            user=member,
            establishment=self.venue,
            role=MerchantMembership.Role.STAFF,
        )
        self.client.force_authenticate(member)

        response = self.client.get(self.url())

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_manager_may(self):
        manager = User.objects.create_user('ibrahima', password='x' * 12)
        MerchantMembership.objects.create(
            user=manager,
            establishment=self.venue,
            role=MerchantMembership.Role.MANAGER,
        )
        self.client.force_authenticate(manager)

        self.assertEqual(
            self.client.get(self.url()).status_code, status.HTTP_200_OK
        )

    def test_a_non_member_gets_404_not_403(self):
        outsider = User.objects.create_user('stranger', password='x' * 12)
        self.client.force_authenticate(outsider)

        response = self.client.get(self.url())

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class ExportRangeTests(ExportTestBase):
    def test_a_backwards_range_is_refused(self):
        response = self.client.get(
            self.url(date_from='2026-08-30', date_to='2026-08-01')
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_enormous_range_is_refused(self):
        """Two requests is an honest answer; a request that builds a decade
        of rows in memory is not."""
        response = self.client.get(
            self.url(date_from='2020-01-01', date_to='2026-08-01')
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_nonsense_dates_say_which_field(self):
        response = self.client.get(self.url(date_from='last-tuesday'))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('date_from', response.data)

    def test_the_range_bounds_are_inclusive(self):
        booking = self.book(days_ago=3)
        day = timezone.localtime(booking.datetime).date().isoformat()

        rows = parsed(self.client.get(self.url(date_from=day, date_to=day)))

        self.assertEqual(len(rows), 2)
