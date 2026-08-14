"""The merchant payments dashboard."""

from datetime import datetime, time, timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space
from payments.models import Payment
from payments.services import start_payment
from payments.tests import FAILING, STUCK
from reservations.models import Reservation


class DashboardTestBase(APITestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.other = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre-ville',
        )
        self.space = Space.objects.create(
            establishment=self.establishment, name='Table 4', capacity=4
        )
        self.other_space = Space.objects.create(
            establishment=self.other, name='Table 1', capacity=2
        )

        self.staff = User.objects.create_user('amadou', password='pw-for-tests')
        self.establishment.staff.add(self.staff)
        self.authenticate(self.staff)

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def book(self, provider=None, days_ahead=1, space=None, name='Guest',
             status_=None):
        when = timezone.localtime() + timedelta(days=days_ahead)
        reservation = Reservation.objects.create(
            space=space or self.space,
            customer_name=name,
            customer_phone='+224 620 00 00 00',
            datetime=timezone.make_aware(
                datetime.combine(when.date(), time(20))
            ),
            party_size=2,
        )
        if provider is not None:
            start_payment(reservation, provider)
            reservation.refresh_from_db()
        if status_ is not None:
            reservation.status = status_
            reservation.save(update_fields=['status'])
        return reservation

    def dashboard(self, establishment=None, **params):
        """Figures for one venue. The endpoint no longer merges across them."""
        params.setdefault(
            'establishment', (establishment or self.establishment).pk
        )
        query = '&'.join(f'{k}={v}' for k, v in params.items())
        response = self.client.get(f'{reverse("payment-dashboard")}?{query}')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data


class AccessTests(DashboardTestBase):
    def test_it_needs_authentication(self):
        self.client.credentials()
        response = self.client.get(reverse('payment-dashboard'))
        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_a_venue_must_be_named(self):
        """Figures are no longer merged, so the caller must say which venue."""
        response = self.client.get(reverse('payment-dashboard'))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('establishment', response.data)

    def test_it_reports_the_named_venue_only(self):
        self.book(Payment.Provider.ORANGE_MONEY, name='Mine')
        self.book(
            Payment.Provider.ORANGE_MONEY, space=self.other_space, name='Theirs'
        )

        data = self.dashboard(date_from=self._from(), date_to=self._to())

        self.assertEqual(
            [e['name'] for e in data['establishments']], ['Le Petit Baobab']
        )
        self.assertEqual(data['reservations']['total'], 1)

    def test_a_venue_the_caller_has_no_membership_in_is_refused(self):
        """Not an empty result — a refusal, even by direct API call."""
        response = self.client.get(
            f'{reverse("payment-dashboard")}?establishment={self.other.pk}'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_user_with_no_memberships_is_refused(self):
        outsider = User.objects.create_user('nobody', password='pw-for-tests')
        self.authenticate(outsider)

        response = self.client.get(
            f'{reverse("payment-dashboard")}?establishment={self.establishment.pk}'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_superuser_may_read_any_venue(self):
        admin = User.objects.create_superuser('root', password='pw-for-tests')
        self.book(
            Payment.Provider.ORANGE_MONEY, space=self.other_space, name='Theirs'
        )
        self.authenticate(admin)

        data = self.dashboard(
            establishment=self.other,
            date_from=self._from(),
            date_to=self._to(),
        )

        self.assertEqual(data['reservations']['total'], 1)

    def _from(self):
        return (timezone.localtime() - timedelta(days=1)).date().isoformat()

    def _to(self):
        return (timezone.localtime() + timedelta(days=10)).date().isoformat()


class TotalsTests(DashboardTestBase):
    def window(self):
        return {
            'date_from': (
                timezone.localtime() - timedelta(days=1)
            ).date().isoformat(),
            'date_to': (
                timezone.localtime() + timedelta(days=10)
            ).date().isoformat(),
        }

    def test_an_empty_period_reports_zero_not_null(self):
        data = self.dashboard(**self.window())

        self.assertEqual(Decimal(data['payments']['collected']), Decimal('0.00'))
        self.assertEqual(Decimal(data['payments']['awaiting']), Decimal('0.00'))
        self.assertEqual(data['payments']['completed_count'], 0)

    def test_completed_payments_are_summed_as_collected(self):
        self.book(Payment.Provider.ORANGE_MONEY, days_ahead=1)
        self.book(Payment.Provider.MTN_MONEY, days_ahead=2)

        data = self.dashboard(**self.window())

        self.assertEqual(
            Decimal(data['payments']['collected']), Decimal('100000.00')
        )
        self.assertEqual(data['payments']['completed_count'], 2)

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_pending_payments_are_reported_as_awaiting(self):
        self.book(Payment.Provider.ORANGE_MONEY)

        data = self.dashboard(**self.window())

        self.assertEqual(Decimal(data['payments']['collected']), Decimal('0.00'))
        self.assertEqual(
            Decimal(data['payments']['awaiting']), Decimal('50000.00')
        )

    @override_settings(PAYMENT_PROVIDERS=FAILING)
    def test_failed_payments_are_reported_separately(self):
        self.book(Payment.Provider.ORANGE_MONEY)

        data = self.dashboard(**self.window())

        self.assertEqual(data['payments']['failed_count'], 1)
        self.assertEqual(Decimal(data['payments']['collected']), Decimal('0.00'))

    def test_cash_bookings_contribute_no_money(self):
        """Cash is settled at the till, not through us."""
        self.book(days_ahead=1)

        data = self.dashboard(**self.window())

        self.assertEqual(data['reservations']['total'], 1)
        self.assertEqual(Decimal(data['payments']['collected']), Decimal('0.00'))

    def test_reservation_statuses_are_counted(self):
        self.book(days_ahead=1)
        self.book(days_ahead=2, status_=Reservation.Status.CANCELLED)
        self.book(Payment.Provider.ORANGE_MONEY, days_ahead=3)

        data = self.dashboard(**self.window())

        self.assertEqual(data['reservations']['total'], 3)
        self.assertEqual(data['reservations']['pending'], 1)
        self.assertEqual(data['reservations']['cancelled'], 1)
        self.assertEqual(data['reservations']['confirmed'], 1)

    def test_bookings_outside_the_window_are_excluded(self):
        self.book(Payment.Provider.ORANGE_MONEY, days_ahead=1)
        self.book(Payment.Provider.ORANGE_MONEY, days_ahead=60)

        data = self.dashboard(**self.window())

        self.assertEqual(data['reservations']['total'], 1)
        self.assertEqual(
            Decimal(data['payments']['collected']), Decimal('50000.00')
        )

    def test_a_malformed_date_is_rejected(self):
        response = self.client.get(
            f'{reverse("payment-dashboard")}?date_from=01-08-2026'
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class ByProviderTests(DashboardTestBase):
    def window(self):
        return {
            'date_from': (
                timezone.localtime() - timedelta(days=1)
            ).date().isoformat(),
            'date_to': (
                timezone.localtime() + timedelta(days=10)
            ).date().isoformat(),
        }

    def test_all_three_providers_are_always_listed(self):
        data = self.dashboard(**self.window())

        self.assertEqual(
            [row['provider'] for row in data['by_provider']],
            ['cash_on_arrival', 'orange_money', 'mtn_money'],
        )

    def test_cash_bookings_are_counted_despite_having_no_payment_row(self):
        """Otherwise the busiest column would simply be missing."""
        self.book(days_ahead=1)
        self.book(days_ahead=2)

        data = self.dashboard(**self.window())
        rows = {row['provider']: row for row in data['by_provider']}

        self.assertEqual(rows['cash_on_arrival']['bookings'], 2)

    def test_money_is_attributed_to_the_right_provider(self):
        self.book(Payment.Provider.ORANGE_MONEY, days_ahead=1)
        self.book(Payment.Provider.ORANGE_MONEY, days_ahead=2)
        self.book(Payment.Provider.MTN_MONEY, days_ahead=3)

        data = self.dashboard(**self.window())
        rows = {row['provider']: row for row in data['by_provider']}

        self.assertEqual(
            Decimal(rows['orange_money']['collected']), Decimal('100000.00')
        )
        self.assertEqual(
            Decimal(rows['mtn_money']['collected']), Decimal('50000.00')
        )
        self.assertEqual(rows['orange_money']['bookings'], 2)


class NeedsAttentionTests(DashboardTestBase):
    def window(self):
        return {
            'date_from': (
                timezone.localtime() - timedelta(days=1)
            ).date().isoformat(),
            'date_to': (
                timezone.localtime() + timedelta(days=10)
            ).date().isoformat(),
        }

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_an_upcoming_unpaid_booking_is_flagged(self):
        self.book(Payment.Provider.ORANGE_MONEY, name='Unpaid Guest')

        data = self.dashboard(**self.window())

        self.assertEqual(len(data['needs_attention']), 1)
        self.assertEqual(
            data['needs_attention'][0]['customer_name'], 'Unpaid Guest'
        )

    def test_a_paid_booking_is_not_flagged(self):
        self.book(Payment.Provider.ORANGE_MONEY, name='Paid Guest')

        self.assertEqual(self.dashboard(**self.window())['needs_attention'], [])

    def test_a_cash_booking_is_not_flagged(self):
        """Cash owes nothing yet, so there is nothing to chase."""
        self.book(name='Cash Guest')

        self.assertEqual(self.dashboard(**self.window())['needs_attention'], [])

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_a_past_booking_is_not_flagged(self):
        """Chasing a payment for a night that already passed is pointless."""
        self.book(Payment.Provider.ORANGE_MONEY, days_ahead=-5)

        self.assertEqual(self.dashboard(**self.window())['needs_attention'], [])

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_a_cancelled_booking_is_not_flagged(self):
        reservation = self.book(Payment.Provider.ORANGE_MONEY)
        reservation.status = Reservation.Status.CANCELLED
        reservation.save(update_fields=['status'])

        self.assertEqual(self.dashboard(**self.window())['needs_attention'], [])

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_another_venues_unpaid_booking_is_not_flagged(self):
        self.book(Payment.Provider.ORANGE_MONEY, space=self.other_space)

        self.assertEqual(self.dashboard(**self.window())['needs_attention'], [])

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_attention_ignores_the_reporting_window(self):
        """A failed payment next month is worth chasing today."""
        self.book(Payment.Provider.ORANGE_MONEY, days_ahead=60, name='Far Off')

        data = self.dashboard(**self.window())

        self.assertEqual(data['reservations']['total'], 0)
        self.assertEqual(len(data['needs_attention']), 1)
