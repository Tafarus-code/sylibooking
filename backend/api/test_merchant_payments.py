"""What the merchant sees about payment, and what they may act on."""

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


class MerchantPaymentTestBase(APITestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )
        self.space = Space.objects.create(
            establishment=self.establishment, name='Table 4', capacity=4
        )
        self.staff = User.objects.create_user('amadou', password='pw-for-tests')
        self.establishment.staff.add(self.staff)

        token = Token.objects.create(user=self.staff)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        self.day = (timezone.localtime() + timedelta(days=1)).date()

    def make_booking(self, hour=19, provider=None, name='Mariama Diallo'):
        reservation = Reservation.objects.create(
            space=self.space,
            customer_name=name,
            customer_phone='+224 620 00 00 00',
            datetime=timezone.make_aware(
                datetime.combine(self.day, time(hour=hour))
            ),
            party_size=2,
        )
        if provider is not None:
            start_payment(reservation, provider)
            reservation.refresh_from_db()
        return reservation

    def row_for(self, response, customer_name):
        for row in response.data['results']:
            if row['customer_name'] == customer_name:
                return row
        raise AssertionError(f'{customer_name} not in the list')


class PaymentVisibleInListTests(MerchantPaymentTestBase):
    def test_cash_booking_reports_cash_and_no_payment_status(self):
        self.make_booking(hour=19)

        row = self.row_for(
            self.client.get(reverse('reservation-list')), 'Mariama Diallo'
        )

        self.assertEqual(row['payment_provider'], 'cash_on_arrival')
        self.assertEqual(row['payment_provider_display'], 'Cash on arrival')
        self.assertIsNone(row['payment_status'])
        self.assertFalse(row['is_paid'])

    def test_paid_orange_money_booking_reports_the_provider(self):
        self.make_booking(hour=19, provider=Payment.Provider.ORANGE_MONEY)

        row = self.row_for(
            self.client.get(reverse('reservation-list')), 'Mariama Diallo'
        )

        self.assertEqual(row['payment_provider'], 'orange_money')
        self.assertEqual(row['payment_provider_display'], 'Orange Money')
        self.assertEqual(row['payment_status'], Payment.Status.COMPLETED)
        self.assertTrue(row['is_paid'])

    def test_paid_mtn_booking_reports_mtn(self):
        self.make_booking(hour=19, provider=Payment.Provider.MTN_MONEY)

        row = self.row_for(
            self.client.get(reverse('reservation-list')), 'Mariama Diallo'
        )

        self.assertEqual(row['payment_provider'], 'mtn_money')
        self.assertEqual(row['payment_provider_display'], 'MTN Mobile Money')
        self.assertTrue(row['is_paid'])

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_unpaid_mobile_money_is_distinguishable_from_cash(self):
        """The merchant must not read an unpaid booking as a cash one."""
        self.make_booking(hour=19, provider=Payment.Provider.ORANGE_MONEY)

        row = self.row_for(
            self.client.get(reverse('reservation-list')), 'Mariama Diallo'
        )

        self.assertEqual(row['payment_provider'], 'orange_money')
        self.assertEqual(row['payment_status'], Payment.Status.PENDING)
        self.assertFalse(row['is_paid'])

    @override_settings(PAYMENT_PROVIDERS=FAILING)
    def test_a_failed_payment_shows_as_failed(self):
        self.make_booking(hour=19, provider=Payment.Provider.ORANGE_MONEY)

        row = self.row_for(
            self.client.get(reverse('reservation-list')), 'Mariama Diallo'
        )

        self.assertEqual(row['payment_status'], Payment.Status.FAILED)
        self.assertFalse(row['is_paid'])

    def test_the_list_carries_amount_and_reference_for_reconciliation(self):
        self.make_booking(hour=19, provider=Payment.Provider.ORANGE_MONEY)

        row = self.row_for(
            self.client.get(reverse('reservation-list')), 'Mariama Diallo'
        )

        self.assertEqual(Decimal(row['payment']['amount']), Decimal('50000'))
        self.assertTrue(row['payment']['provider_reference'])

    def test_a_mixed_day_reports_each_booking_separately(self):
        self.make_booking(hour=18, name='Cash Customer')
        self.make_booking(
            hour=20,
            provider=Payment.Provider.ORANGE_MONEY,
            name='Orange Customer',
        )
        self.make_booking(
            hour=22, provider=Payment.Provider.MTN_MONEY, name='MTN Customer'
        )

        response = self.client.get(reverse('reservation-list'))

        self.assertIsNone(self.row_for(response, 'Cash Customer')['payment_status'])
        self.assertTrue(self.row_for(response, 'Orange Customer')['is_paid'])
        self.assertEqual(
            self.row_for(response, 'MTN Customer')['payment_provider'],
            'mtn_money',
        )

    def test_listing_a_day_does_not_query_per_booking(self):
        """Payments are prefetched; a busy night must not melt the database."""
        for hour in range(12, 22):
            self.make_booking(
                hour=hour,
                provider=Payment.Provider.ORANGE_MONEY,
                name=f'Customer {hour}',
            )

        with self.assertNumQueries(4):
            # count, page of reservations, prefetched payments, and the
            # session/auth lookup for the token.
            self.client.get(reverse('reservation-list'))


class PaymentVisibleInDetailTests(MerchantPaymentTestBase):
    def test_detail_carries_the_provider_reference_and_amount(self):
        reservation = self.make_booking(
            hour=19, provider=Payment.Provider.ORANGE_MONEY
        )

        response = self.client.get(
            reverse('reservation-detail', args=[reservation.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['payment_provider'], 'orange_money')
        self.assertTrue(response.data['payment']['provider_reference'])
        self.assertEqual(
            Decimal(response.data['payment']['amount']), Decimal('50000')
        )

    def test_detail_of_a_cash_booking_has_no_payment(self):
        reservation = self.make_booking(hour=19)

        response = self.client.get(
            reverse('reservation-detail', args=[reservation.pk])
        )

        self.assertIsNone(response.data['payment'])
        self.assertEqual(response.data['payment_provider'], 'cash_on_arrival')


class ConfirmationRuleTests(MerchantPaymentTestBase):
    """One rule: cash confirms on trust, mobile money confirms on money."""

    def confirm(self, reservation):
        return self.client.post(
            reverse('reservation-confirm', args=[reservation.pk])
        )

    def test_cash_can_be_confirmed_before_the_customer_pays(self):
        """The whole point of cash on arrival."""
        reservation = self.make_booking(hour=19)

        response = self.confirm(reservation)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.CONFIRMED)

    def test_a_paid_mobile_money_booking_can_be_confirmed(self):
        reservation = self.make_booking(
            hour=19, provider=Payment.Provider.ORANGE_MONEY
        )
        # start_payment already confirmed it; put it back to pending so the
        # merchant action is what is under test.
        reservation.status = Reservation.Status.PENDING
        reservation.save(update_fields=['status'])

        response = self.confirm(reservation)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.CONFIRMED)

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_an_unpaid_mobile_money_booking_cannot_be_force_confirmed(self):
        """Straight at the API, with no button to hide behind."""
        reservation = self.make_booking(
            hour=19, provider=Payment.Provider.ORANGE_MONEY
        )
        self.assertEqual(reservation.status, Reservation.Status.PENDING)

        response = self.confirm(reservation)

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('pending', response.data['detail'].lower())
        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.PENDING)

    @override_settings(PAYMENT_PROVIDERS=FAILING)
    def test_a_failed_mobile_money_booking_cannot_be_confirmed(self):
        reservation = self.make_booking(
            hour=19, provider=Payment.Provider.ORANGE_MONEY
        )

        response = self.confirm(reservation)

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('failed', response.data['detail'].lower())
        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.PENDING)

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_the_refusal_says_which_provider_and_state(self):
        """A merchant on the phone to a customer needs to know why."""
        reservation = self.make_booking(
            hour=19, provider=Payment.Provider.ORANGE_MONEY
        )

        response = self.confirm(reservation)

        self.assertEqual(response.data['payment_provider'], 'orange_money')
        self.assertEqual(response.data['payment_status'], Payment.Status.PENDING)

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_it_becomes_confirmable_once_the_payment_lands(self):
        reservation = self.make_booking(
            hour=19, provider=Payment.Provider.ORANGE_MONEY
        )
        self.assertEqual(
            self.confirm(reservation).status_code, status.HTTP_409_CONFLICT
        )

        payment = reservation.latest_payment
        payment.status = Payment.Status.COMPLETED
        payment.save(update_fields=['status'])

        self.assertEqual(
            self.confirm(reservation).status_code, status.HTTP_200_OK
        )

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_an_unpaid_booking_can_still_be_cancelled(self):
        """Blocked from confirming is not blocked from dealing with it."""
        reservation = self.make_booking(
            hour=19, provider=Payment.Provider.ORANGE_MONEY
        )

        response = self.client.post(
            reverse('reservation-cancel', args=[reservation.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        reservation.refresh_from_db()
        self.assertEqual(reservation.status, Reservation.Status.CANCELLED)

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_can_confirm_flag_matches_what_the_server_will_allow(self):
        unpaid = self.make_booking(
            hour=19, provider=Payment.Provider.ORANGE_MONEY, name='Unpaid'
        )
        cash = self.make_booking(hour=21, name='Cash')

        response = self.client.get(reverse('reservation-list'))

        self.assertFalse(self.row_for(response, 'Unpaid')['can_confirm'])
        self.assertTrue(self.row_for(response, 'Cash')['can_confirm'])
        # And the server agrees with its own flag.
        self.assertEqual(
            self.confirm(unpaid).status_code, status.HTTP_409_CONFLICT
        )
        self.assertEqual(self.confirm(cash).status_code, status.HTTP_200_OK)
