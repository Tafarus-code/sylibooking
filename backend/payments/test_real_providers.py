"""Orange and MTN, against recorded answers rather than a sandbox.

Never against the live sandbox, deliberately. A test that needs somebody
else's server to be up is a test that fails for reasons that have nothing to
do with this code, and a suite people learn to re-run is a suite people learn
to ignore.

What is covered is the part that is ours: the vocabulary each provider uses
mapped onto `Payment.Status`, what happens when a token goes stale, and the
rule that decides whether a call may be repeated. What is not covered — and
cannot be until credentials exist — is whether their field names are what
their documentation says.
"""

from decimal import Decimal

import requests
from django.core.cache import cache
from django.test import TestCase, override_settings

from establishments.models import Establishment, Space
from payments.models import Payment
from payments.mtn import MtnMoneyProvider, msisdn
from payments.orange import OrangeMoneyProvider
from payments.providers import PaymentError
from reservations.models import Reservation


class FakeResponse:
    def __init__(self, status_code=200, json_body=None, text=''):
        self.status_code = status_code
        self._json = json_body
        self.text = text or ''
        self.content = b'x' if (json_body is not None or text) else b''

    def json(self):
        if self._json is None:
            raise ValueError('no json')
        return self._json


class FakeSession:
    """Answers with whatever it was told to, and remembers what it was asked."""

    def __init__(self, *answers):
        self.answers = list(answers)
        self.calls = []

    def request(self, method, url, **kwargs):
        self.calls.append({'method': method, 'url': url, **kwargs})
        if not self.answers:
            return FakeResponse(200, {})
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return answer


ORANGE = {
    'client_id': 'id',
    'client_secret': 'secret',
    'merchant_key': 'merchant',
    'token_url': 'https://example.test/oauth/v3/token',
    'payment_url': 'https://example.test/webpayment',
    'status_url': 'https://example.test/transactionstatus',
    'currency': 'GNF',
    'notif_url': 'https://sylibooking.test/api/payments/callbacks/orange/s/',
}

MTN = {
    'base_url': 'https://example.test',
    'api_user': 'user',
    'api_key': 'key',
    'subscription_key': 'sub',
    'environment': 'sandbox',
    'currency': 'GNF',
}


class ProviderTestBase(TestCase):
    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)
        venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        table = Space.objects.create(
            establishment=venue, name='Table 1', capacity=4
        )
        self.booking = Reservation.objects.create(
            space=table,
            customer_name='Mariama Diallo',
            customer_phone='+224 620 00 00 01',
            datetime='2026-09-01T19:00:00Z',
            party_size=2,
        )


@override_settings(ORANGE_MONEY=ORANGE)
class OrangeMoneyTests(ProviderTestBase):
    def test_a_payment_returns_our_own_order_id(self):
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
            FakeResponse(
                200,
                {
                    'pay_token': 'PAY',
                    'payment_url': 'https://pay.test/x',
                    'notif_token': 'NOTIF',
                },
            ),
        )

        reference = OrangeMoneyProvider(session=session).initiate_payment(
            self.booking, Decimal('50000.00')
        )

        self.assertTrue(reference.startswith('SYLI-'))
        body = session.calls[1]['json']
        self.assertEqual(body['order_id'], reference)
        # An integer, not "50000.00": Orange's parser reads a decimal string
        # as a string and refuses it.
        self.assertEqual(body['amount'], 50000)
        self.assertIsInstance(body['amount'], int)

    def test_the_token_is_reused_rather_than_refetched(self):
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
            FakeResponse(200, {'pay_token': 'PAY'}),
            FakeResponse(200, {'pay_token': 'PAY2'}),
        )
        provider = OrangeMoneyProvider(session=session)

        provider.initiate_payment(self.booking, Decimal('50000.00'))
        provider.initiate_payment(self.booking, Decimal('50000.00'))

        token_calls = [c for c in session.calls if 'token' in c['url']]
        self.assertEqual(len(token_calls), 1)

    def test_a_stale_token_is_refreshed_once(self):
        session = FakeSession(
            FakeResponse(200, {'access_token': 'old', 'expires_in': 3600}),
            FakeResponse(401, text='expired'),
            FakeResponse(200, {'access_token': 'new', 'expires_in': 3600}),
            FakeResponse(200, {'pay_token': 'PAY'}),
        )

        reference = OrangeMoneyProvider(session=session).initiate_payment(
            self.booking, Decimal('50000.00')
        )

        self.assertTrue(reference.startswith('SYLI-'))

    def test_a_payment_request_is_never_retried(self):
        """A repeat is a second prompt on somebody's phone."""
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
            requests.ConnectionError('boom'),
        )

        with self.assertRaises(PaymentError):
            OrangeMoneyProvider(session=session).initiate_payment(
                self.booking, Decimal('50000.00')
            )

        payment_calls = [c for c in session.calls if 'webpayment' in c['url']]
        self.assertEqual(len(payment_calls), 1)

    def test_statuses_map_onto_ours(self):
        cases = {
            'SUCCESS': Payment.Status.COMPLETED,
            'PENDING': Payment.Status.PENDING,
            'INITIATED': Payment.Status.PENDING,
            'FAILED': Payment.Status.FAILED,
            'EXPIRED': Payment.Status.FAILED,
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                # Cleared per case: the access token is cached between calls
                # (which is the point of it), so a second case would consume
                # the stubbed token response as if it were a status.
                cache.clear()
                cache.set(
                    'orange-money:context:SYLI-1',
                    {'pay_token': 'PAY', 'amount': 50000},
                )
                session = FakeSession(
                    FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
                    FakeResponse(200, {'status': raw}),
                )
                status = OrangeMoneyProvider(session=session).check_status(
                    'SYLI-1'
                )
                self.assertEqual(status, expected)

    def test_an_unknown_status_is_pending_not_failed(self):
        """**The rule that protects a customer mid-payment.**

        A word nobody has seen is far more likely a new intermediate state
        than a lost payment, and calling it failed cancels a booking somebody
        is in the middle of paying for.
        """
        cache.set(
            'orange-money:context:SYLI-1', {'pay_token': 'PAY', 'amount': 50000}
        )
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
            FakeResponse(200, {'status': 'AWAITING_CONFIRMATION'}),
        )

        status = OrangeMoneyProvider(session=session).check_status('SYLI-1')

        self.assertEqual(status, Payment.Status.PENDING)

    def test_missing_credentials_are_a_clear_refusal(self):
        with override_settings(ORANGE_MONEY={**ORANGE, 'client_id': ''}):
            with self.assertRaises(PaymentError):
                OrangeMoneyProvider(session=FakeSession()).access_token()

    def test_refunds_say_they_are_not_possible_here(self):
        # Rather than reporting success for something nobody was asked to do.
        with self.assertRaises(PaymentError):
            OrangeMoneyProvider(session=FakeSession()).refund('SYLI-1', 50000)


@override_settings(MTN_MOMO=MTN)
class MtnMoneyTests(ProviderTestBase):
    def test_the_reference_is_ours_and_travels_as_the_idempotency_key(self):
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
            FakeResponse(202),
        )

        reference = MtnMoneyProvider(session=session).initiate_payment(
            self.booking, Decimal('50000.00')
        )

        self.assertEqual(
            session.calls[1]['headers']['X-Reference-Id'], reference
        )

    def test_the_payer_number_is_cleaned(self):
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
            FakeResponse(202),
        )

        MtnMoneyProvider(session=session).initiate_payment(
            self.booking, Decimal('50000.00')
        )

        self.assertEqual(
            session.calls[1]['json']['payer']['partyId'], '224620000001'
        )

    def test_a_booking_with_no_number_cannot_be_charged(self):
        self.booking.customer_phone = ''
        self.booking.save()
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600})
        )

        with self.assertRaises(PaymentError):
            MtnMoneyProvider(session=session).initiate_payment(
                self.booking, Decimal('50000.00')
            )

    def test_statuses_map_onto_ours(self):
        cases = {
            'SUCCESSFUL': Payment.Status.COMPLETED,
            'PENDING': Payment.Status.PENDING,
            'FAILED': Payment.Status.FAILED,
            'REJECTED': Payment.Status.FAILED,
            'TIMEOUT': Payment.Status.FAILED,
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                # See the Orange equivalent: the token cache outlives a case.
                cache.clear()
                session = FakeSession(
                    FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
                    FakeResponse(200, {'status': raw}),
                )
                self.assertEqual(
                    MtnMoneyProvider(session=session).check_status('ref'),
                    expected,
                )

    def test_an_unknown_status_is_pending(self):
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
            FakeResponse(200, {'status': 'SOMETHING_NEW'}),
        )

        self.assertEqual(
            MtnMoneyProvider(session=session).check_status('ref'),
            Payment.Status.PENDING,
        )

    def test_a_status_check_is_retried(self):
        """It changes nothing, so a blip should not lose a payment."""
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600}),
            requests.ConnectionError('blip'),
            FakeResponse(200, {'status': 'SUCCESSFUL'}),
        )

        status = MtnMoneyProvider(session=session).check_status('ref')

        self.assertEqual(status, Payment.Status.COMPLETED)

    def test_a_refund_without_a_disbursement_key_is_refused(self):
        session = FakeSession(
            FakeResponse(200, {'access_token': 't', 'expires_in': 3600})
        )

        with self.assertRaises(PaymentError):
            MtnMoneyProvider(session=session).refund('ref', 50000)

    def test_msisdn_strips_everything_that_is_not_a_digit(self):
        self.assertEqual(msisdn('+224 620 00 00 01'), '224620000001')
        self.assertEqual(msisdn(None), '')
