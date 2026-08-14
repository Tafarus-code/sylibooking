"""Paying for a booking through the API, as the customer app does."""

from datetime import datetime, time, timedelta
from decimal import Decimal

from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from establishments.models import Establishment, Space
from payments.models import Payment
from payments.tests import FAILING, STUCK
from reservations.models import Reservation


class PaymentApiTestBase(APITestCase):
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
        tomorrow = (timezone.localtime() + timedelta(days=1)).date()
        self.slot = timezone.make_aware(datetime.combine(tomorrow, time(19)))

    def book(self, provider=None, hour_offset=0, **overrides):
        payload = {
            'space': self.space.pk,
            'customer_name': 'Mariama Diallo',
            'customer_phone': '+224 620 00 00 00',
            'datetime': (
                self.slot + timedelta(hours=hour_offset)
            ).isoformat(),
            'party_size': 2,
        }
        if provider is not None:
            payload['payment_provider'] = provider
        payload.update(overrides)
        return self.client.post(
            reverse('reservation-list'), payload, format='json'
        )


class BookingWithMobileMoneyTests(PaymentApiTestBase):
    def test_a_paid_booking_comes_back_confirmed(self):
        response = self.book(Payment.Provider.ORANGE_MONEY)

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['status'], Reservation.Status.CONFIRMED)

    def test_the_response_carries_the_payment(self):
        response = self.book(Payment.Provider.ORANGE_MONEY)

        payment = response.data['payment']
        self.assertIsNotNone(payment)
        self.assertEqual(payment['status'], Payment.Status.COMPLETED)
        self.assertEqual(payment['provider'], Payment.Provider.ORANGE_MONEY)
        self.assertTrue(payment['provider_reference'])

    def test_the_amount_is_not_client_supplied(self):
        """A client must never get to say what it owes."""
        response = self.book(Payment.Provider.ORANGE_MONEY, amount='1')

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(
            Decimal(response.data['payment']['amount']), Decimal('50000')
        )

    def test_an_unknown_provider_is_rejected(self):
        response = self.book('bitcoin')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('payment_provider', response.data)
        self.assertEqual(Reservation.objects.count(), 0)

    @override_settings(PAYMENT_PROVIDERS=FAILING)
    def test_a_failed_payment_still_creates_the_booking_but_pending(self):
        response = self.book(Payment.Provider.ORANGE_MONEY)

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['status'], Reservation.Status.PENDING)
        self.assertEqual(
            response.data['payment']['status'], Payment.Status.FAILED
        )


class BookingWithCashTests(PaymentApiTestBase):
    def test_cash_is_the_default(self):
        """Omitting the field must behave exactly as before payments existed."""
        response = self.book()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['status'], Reservation.Status.PENDING)
        self.assertIsNone(response.data['payment'])
        self.assertEqual(Payment.objects.count(), 0)

    def test_cash_chosen_explicitly_behaves_the_same(self):
        response = self.book(Payment.Provider.CASH_ON_ARRIVAL)

        self.assertEqual(response.data['status'], Reservation.Status.PENDING)
        self.assertIsNone(response.data['payment'])
        self.assertEqual(Payment.objects.count(), 0)


class PaymentStatusEndpointTests(PaymentApiTestBase):
    def status_url(self, reference):
        return reverse('reservation-payment-status', args=[reference])

    def test_reports_a_completed_payment(self):
        booked = self.book(Payment.Provider.ORANGE_MONEY)
        response = self.client.get(self.status_url(booked.data['reference']))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            response.data['payment']['status'], Payment.Status.COMPLETED
        )
        self.assertEqual(
            response.data['reservation']['status'],
            Reservation.Status.CONFIRMED,
        )

    def test_a_cash_booking_says_so_rather_than_erroring(self):
        booked = self.book(Payment.Provider.CASH_ON_ARRIVAL)
        response = self.client.get(self.status_url(booked.data['reference']))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIsNone(response.data['payment'])
        self.assertIn('on arrival', response.data['detail'])

    def test_polling_confirms_a_payment_that_settles_later(self):
        """The customer approves on their handset after the app gave up asking."""
        with override_settings(PAYMENT_PROVIDERS=STUCK):
            booked = self.book(Payment.Provider.ORANGE_MONEY)

        self.assertEqual(booked.data['status'], Reservation.Status.PENDING)

        # The provider now reports it settled.
        response = self.client.get(self.status_url(booked.data['reference']))

        self.assertEqual(
            response.data['payment']['status'], Payment.Status.COMPLETED
        )
        self.assertEqual(
            response.data['reservation']['status'],
            Reservation.Status.CONFIRMED,
        )

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_an_unsettled_payment_leaves_the_booking_pending(self):
        booked = self.book(Payment.Provider.ORANGE_MONEY)
        response = self.client.get(self.status_url(booked.data['reference']))

        self.assertEqual(
            response.data['payment']['status'], Payment.Status.PENDING
        )
        self.assertEqual(
            response.data['reservation']['status'], Reservation.Status.PENDING
        )

    def test_an_unknown_reference_is_a_404(self):
        url = self.status_url('00000000-0000-0000-0000-000000000000')
        self.assertEqual(
            self.client.get(url).status_code, status.HTTP_404_NOT_FOUND
        )

    def test_the_endpoint_needs_no_account(self):
        """Customers have none; the reference is the credential."""
        booked = self.book(Payment.Provider.ORANGE_MONEY)
        self.client.credentials()

        response = self.client.get(self.status_url(booked.data['reference']))
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class PaymentAndCancellationTests(PaymentApiTestBase):
    def test_a_paid_booking_can_still_be_cancelled_by_the_customer(self):
        booked = self.book(Payment.Provider.ORANGE_MONEY)
        reference = booked.data['reference']

        response = self.client.post(
            reverse('reservation-cancel-by-reference', args=[reference])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], Reservation.Status.CANCELLED)

    def test_polling_after_cancelling_does_not_reinstate_the_booking(self):
        """A completed payment must not undo the customer's cancellation."""
        with override_settings(PAYMENT_PROVIDERS=STUCK):
            booked = self.book(Payment.Provider.ORANGE_MONEY)
        reference = booked.data['reference']

        self.client.post(
            reverse('reservation-cancel-by-reference', args=[reference])
        )

        response = self.client.get(
            reverse('reservation-payment-status', args=[reference])
        )

        self.assertEqual(
            response.data['payment']['status'], Payment.Status.COMPLETED
        )
        self.assertEqual(
            response.data['reservation']['status'],
            Reservation.Status.CANCELLED,
        )
