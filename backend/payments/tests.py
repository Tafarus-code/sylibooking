"""The payment flow, against doubles rather than a provider sandbox."""

from datetime import datetime, time, timedelta
from decimal import Decimal

from django.test import TestCase, override_settings
from django.utils import timezone

from establishments.models import Establishment, Space
from reservations.models import Reservation

from .models import Payment
from .providers import (
    MockPaymentProvider,
    PaymentError,
    PaymentProvider,
    get_payment_provider,
)
from .services import refresh_payment, start_payment


class FailingPaymentProvider(PaymentProvider):
    """Accepts the request, then reports the payment failed.

    A customer whose mobile money balance is short looks like this: the
    request goes through, the transfer does not.
    """

    def initiate_payment(self, reservation, amount):
        return 'FAIL-REF-0001'

    def check_status(self, provider_reference):
        return Payment.Status.FAILED


class PendingPaymentProvider(PaymentProvider):
    """Never settles — the customer has not approved it on their handset."""

    def initiate_payment(self, reservation, amount):
        return 'PENDING-REF-0001'

    def check_status(self, provider_reference):
        return Payment.Status.PENDING


class UnreachablePaymentProvider(PaymentProvider):
    """The provider's API is down."""

    def initiate_payment(self, reservation, amount):
        raise PaymentError('gateway timeout')

    def check_status(self, provider_reference):
        raise PaymentError('gateway timeout')


FAILING = {'orange_money': f'{__name__}.FailingPaymentProvider'}
STUCK = {'orange_money': f'{__name__}.PendingPaymentProvider'}
UNREACHABLE = {'orange_money': f'{__name__}.UnreachablePaymentProvider'}


class PaymentTestBase(TestCase):
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
        self.reservation = Reservation.objects.create(
            space=self.space,
            customer_name='Mariama Diallo',
            customer_phone='+224 620 00 00 00',
            datetime=timezone.make_aware(datetime.combine(tomorrow, time(19))),
            party_size=2,
        )


class MockProviderTests(PaymentTestBase):
    def setUp(self):
        super().setUp()
        self.provider = MockPaymentProvider()

    def test_initiate_returns_a_reference(self):
        reference = self.provider.initiate_payment(
            self.reservation, Decimal('50000')
        )
        self.assertTrue(reference.startswith('MOCK-'))

    def test_references_are_unique_per_call(self):
        first = self.provider.initiate_payment(
            self.reservation, Decimal('50000')
        )
        second = self.provider.initiate_payment(
            self.reservation, Decimal('50000')
        )
        self.assertNotEqual(first, second)

    def test_check_status_always_completes(self):
        self.assertEqual(
            self.provider.check_status('MOCK-ANYTHING'),
            Payment.Status.COMPLETED,
        )


class ProviderLookupTests(TestCase):
    def test_configured_provider_is_returned(self):
        self.assertIsInstance(
            get_payment_provider('orange_money'), MockPaymentProvider
        )

    def test_mtn_resolves_too(self):
        self.assertIsInstance(
            get_payment_provider('mtn_money'), MockPaymentProvider
        )

    def test_an_unconfigured_provider_raises(self):
        with self.assertRaises(PaymentError):
            get_payment_provider('bitcoin')

    @override_settings(PAYMENT_PROVIDERS=FAILING)
    def test_the_backend_is_swappable_by_settings(self):
        """Real integrations arrive as configuration, not a rewrite."""
        self.assertIsInstance(
            get_payment_provider('orange_money'), FailingPaymentProvider
        )


class SuccessfulPaymentTests(PaymentTestBase):
    def test_a_completed_payment_confirms_the_reservation(self):
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )

        self.assertEqual(payment.status, Payment.Status.COMPLETED)
        self.reservation.refresh_from_db()
        self.assertEqual(
            self.reservation.status, Reservation.Status.CONFIRMED
        )

    def test_the_payment_records_the_provider_reference(self):
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )
        self.assertTrue(payment.provider_reference)

    def test_the_amount_comes_from_settings_not_the_caller(self):
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )
        self.assertEqual(payment.amount, Decimal('50000'))

    @override_settings(RESERVATION_DEPOSIT_AMOUNT=Decimal('75000'))
    def test_the_deposit_amount_is_configurable(self):
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )
        self.assertEqual(payment.amount, Decimal('75000'))

    def test_mtn_works_the_same_way(self):
        payment = start_payment(self.reservation, Payment.Provider.MTN_MONEY)

        self.assertEqual(payment.status, Payment.Status.COMPLETED)
        self.reservation.refresh_from_db()
        self.assertEqual(
            self.reservation.status, Reservation.Status.CONFIRMED
        )


class FailedPaymentTests(PaymentTestBase):
    @override_settings(PAYMENT_PROVIDERS=FAILING)
    def test_a_failed_payment_leaves_the_reservation_pending(self):
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )

        self.assertEqual(payment.status, Payment.Status.FAILED)
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.status, Reservation.Status.PENDING)

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_a_payment_awaiting_approval_leaves_it_pending(self):
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )

        self.assertEqual(payment.status, Payment.Status.PENDING)
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.status, Reservation.Status.PENDING)

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_a_stuck_payment_confirms_once_it_settles(self):
        """Polling is how the customer's app learns the money arrived."""
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )
        self.assertEqual(payment.status, Payment.Status.PENDING)

        with override_settings(PAYMENT_PROVIDERS=self._mock_settings()):
            refresh_payment(payment)

        payment.refresh_from_db()
        self.reservation.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.COMPLETED)
        self.assertEqual(
            self.reservation.status, Reservation.Status.CONFIRMED
        )

    @staticmethod
    def _mock_settings():
        return {'orange_money': 'payments.providers.MockPaymentProvider'}

    @override_settings(PAYMENT_PROVIDERS=UNREACHABLE)
    def test_an_unreachable_provider_fails_the_payment_not_the_booking(self):
        """Nothing was taken, so the booking survives for another attempt."""
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )

        self.assertEqual(payment.status, Payment.Status.FAILED)
        self.assertIsNone(payment.provider_reference)
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.status, Reservation.Status.PENDING)

    @override_settings(PAYMENT_PROVIDERS=STUCK)
    def test_an_unreachable_check_leaves_the_payment_pending(self):
        """Not knowing is not the same as knowing it failed."""
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )

        with override_settings(PAYMENT_PROVIDERS=UNREACHABLE):
            refresh_payment(payment)

        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.PENDING)


class CashOnArrivalTests(PaymentTestBase):
    def test_cash_creates_no_payment_record(self):
        payment = start_payment(
            self.reservation, Payment.Provider.CASH_ON_ARRIVAL
        )

        self.assertIsNone(payment)
        self.assertEqual(self.reservation.payments.count(), 0)

    def test_cash_leaves_the_reservation_pending(self):
        """Unchanged: the merchant confirms these by hand, as today."""
        start_payment(self.reservation, Payment.Provider.CASH_ON_ARRIVAL)

        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.status, Reservation.Status.PENDING)


class ConfirmationGuardTests(PaymentTestBase):
    def test_a_late_payment_does_not_reinstate_a_cancelled_booking(self):
        """The table was given away; paying afterwards must not take it back."""
        self.reservation.status = Reservation.Status.CANCELLED
        self.reservation.save(update_fields=['status'])

        start_payment(self.reservation, Payment.Provider.ORANGE_MONEY)

        self.reservation.refresh_from_db()
        self.assertEqual(
            self.reservation.status, Reservation.Status.CANCELLED
        )

    def test_a_payment_does_not_reopen_a_completed_visit(self):
        self.reservation.status = Reservation.Status.COMPLETED
        self.reservation.save(update_fields=['status'])

        start_payment(self.reservation, Payment.Provider.ORANGE_MONEY)

        self.reservation.refresh_from_db()
        self.assertEqual(
            self.reservation.status, Reservation.Status.COMPLETED
        )

    def test_refreshing_a_completed_payment_is_a_no_op(self):
        payment = start_payment(
            self.reservation, Payment.Provider.ORANGE_MONEY
        )
        self.assertEqual(payment.status, Payment.Status.COMPLETED)

        with override_settings(PAYMENT_PROVIDERS=FAILING):
            refresh_payment(payment)

        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.COMPLETED)


class PaymentModelTests(PaymentTestBase):
    def test_str_is_readable(self):
        payment = Payment.objects.create(
            reservation=self.reservation,
            provider=Payment.Provider.ORANGE_MONEY,
            amount=Decimal('50000'),
        )
        self.assertIn('Orange Money', str(payment))
        self.assertIn('Pending', str(payment))

    def test_payments_start_pending(self):
        payment = Payment.objects.create(
            reservation=self.reservation,
            provider=Payment.Provider.MTN_MONEY,
            amount=Decimal('50000'),
        )
        self.assertEqual(payment.status, Payment.Status.PENDING)

    def test_mobile_money_is_distinguished_from_cash(self):
        mobile = Payment(provider=Payment.Provider.ORANGE_MONEY)
        cash = Payment(provider=Payment.Provider.CASH_ON_ARRIVAL)

        self.assertTrue(mobile.is_mobile_money)
        self.assertFalse(cash.is_mobile_money)

    def test_deleting_a_reservation_takes_its_payments(self):
        Payment.objects.create(
            reservation=self.reservation,
            provider=Payment.Provider.ORANGE_MONEY,
            amount=Decimal('50000'),
        )
        self.reservation.delete()
        self.assertEqual(Payment.objects.count(), 0)
