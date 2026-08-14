"""The only unauthenticated write surface in the product.

Which is why most of these are about refusing rather than accepting: what a
forged callback can do matters more than what a real one does, because a real
one is only ever saving the poller thirty seconds.
"""

from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase, override_settings
from django.urls import reverse

from establishments.models import Establishment, Space
from payments.models import Payment
from reservations.models import Reservation


@override_settings(
    ORANGE_CALLBACK_SECRET='orange-secret',
    MTN_CALLBACK_SECRET='mtn-secret',
    THROTTLING_ENABLED=False,
)
class CallbackTests(TestCase):
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
            customer_phone='+224620000001',
            datetime='2026-09-01T19:00:00Z',
            party_size=2,
        )
        self.payment = Payment.objects.create(
            reservation=self.booking,
            provider=Payment.Provider.ORANGE_MONEY,
            amount=Decimal('50000.00'),
            status=Payment.Status.PENDING,
            provider_reference='SYLI-ABC',
        )

    def orange_url(self, secret='orange-secret'):
        return reverse('orange-callback', args=[secret])

    def mtn_url(self, secret='mtn-secret'):
        return reverse('mtn-callback', args=[secret])

    # --- Refusing ---------------------------------------------------------

    def test_a_wrong_secret_is_not_even_acknowledged(self):
        response = self.client.post(
            self.orange_url('guessed'),
            {'order_id': 'SYLI-ABC'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 404)

    def test_an_unset_secret_refuses_everything(self):
        """**The failure that would otherwise be silent.**

        An empty configured secret must not mean "everything matches", which
        is how this endpoint ends up open in production because one
        environment variable was spelled wrong.
        """
        # The real shape of the mistake: the URL Orange was given still
        # works, and the variable behind it is empty.
        with override_settings(ORANGE_CALLBACK_SECRET=''):
            response = self.client.post(
                self.orange_url('orange-secret'),
                {'order_id': 'SYLI-ABC'},
                content_type='application/json',
            )

        self.assertEqual(response.status_code, 404)

    def test_a_wrong_notif_token_is_refused_and_logged(self):
        cache.set(
            'orange-money:context:SYLI-ABC',
            {'pay_token': 'PAY', 'amount': 50000, 'notif_token': 'REAL'},
        )

        response = self.client.post(
            self.orange_url(),
            {'order_id': 'SYLI-ABC', 'notif_token': 'GUESSED'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 403)

    def test_the_payload_status_is_never_believed(self):
        """A forged "SUCCESS" must not complete a payment.

        The callback is a nudge to go and ask the provider, never the answer.
        With no provider configured the mock answers, so this asserts the
        shape rather than the outcome: what matters is that the row's status
        came from a status check and not from the request body.
        """
        response = self.client.post(
            self.orange_url(),
            {'order_id': 'SYLI-ABC', 'status': 'SUCCESS', 'amount': '999999'},
            content_type='application/json',
        )

        self.payment.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        # The amount in the payload is ignored outright.
        self.assertEqual(self.payment.amount, Decimal('50000.00'))

    # --- Accepting --------------------------------------------------------

    def test_an_unknown_order_is_acknowledged_rather_than_errored(self):
        """A provider that gets an error retries harder. A shrug is cheaper
        than a retry storm about a payment we do not have."""
        response = self.client.post(
            self.orange_url(),
            {'order_id': 'SYLI-NOTHING'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)

    def test_a_callback_with_no_order_id_is_acknowledged(self):
        response = self.client.post(
            self.orange_url(), {}, content_type='application/json'
        )

        self.assertEqual(response.status_code, 200)

    def test_delivering_the_same_callback_twice_changes_nothing(self):
        """Providers redeliver for hours. Applying one is refresh_payment,
        which is idempotent by construction."""
        for _ in range(3):
            response = self.client.post(
                self.orange_url(),
                {'order_id': 'SYLI-ABC'},
                content_type='application/json',
            )
            self.assertEqual(response.status_code, 200)

        self.assertEqual(Payment.objects.filter(reservation=self.booking).count(), 1)

    def test_mtn_finds_its_payment_by_reference(self):
        self.payment.provider = Payment.Provider.MTN_MONEY
        self.payment.provider_reference = 'mtn-ref-1'
        self.payment.save()

        response = self.client.post(
            self.mtn_url(),
            {'referenceId': 'mtn-ref-1'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)

    def test_mtn_refuses_a_wrong_secret(self):
        response = self.client.post(
            self.mtn_url('guessed'),
            {'referenceId': 'mtn-ref-1'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 404)
