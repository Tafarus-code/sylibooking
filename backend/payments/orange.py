"""Orange Money, against the Web Payment API.

The flow Orange offers is not a silent debit. It issues a payment URL and a
`pay_token`; the customer authorises on their own handset, and we find out
either by polling the transaction status or by the notification Orange posts
to `notif_url`. Both paths are wired, because in this market either can be
the one that works on a given evening.

**Every endpoint and field name here is settings-driven.** Orange's contract
differs by country and by merchant agreement, and this file was written from
the published shape rather than from your account. When the sandbox
credentials arrive, check the two URLs and the currency against what Orange
actually sent you and change settings, not code. That is the whole reason
they are settings.

What this adapter deliberately does not do is decide anything about a
booking. It answers "what does Orange say about this transaction", and
payments/services.py decides what that means.
"""

import logging
import uuid

from django.conf import settings
from django.core.cache import cache

from .http import ProviderHttpError, ProviderRefused, request
from .models import Payment
from .providers import PaymentError, PaymentProvider

logger = logging.getLogger(__name__)

#: Orange's own vocabulary, mapped onto ours.
#:
#: INITIATED and PENDING both mean the customer has not finished — they are
#: not failures, and calling them failures is how a customer gets told their
#: payment broke while their phone is still showing the prompt.
STATUS_MAP = {
    'SUCCESS': Payment.Status.COMPLETED,
    'SUCCESSFUL': Payment.Status.COMPLETED,
    'INITIATED': Payment.Status.PENDING,
    'PENDING': Payment.Status.PENDING,
    'FAILED': Payment.Status.FAILED,
    'EXPIRED': Payment.Status.FAILED,
    'CANCELLED': Payment.Status.FAILED,
    'REJECTED': Payment.Status.FAILED,
}

#: Where the access token is kept between calls. Orange's tokens last about
#: an hour; fetching one per request would triple the calls and get us
#: throttled by our own chattiness.
TOKEN_CACHE_KEY = 'orange-money:access-token'


def _config():
    return getattr(settings, 'ORANGE_MONEY', {})


class OrangeMoneyProvider(PaymentProvider):
    """Orange Money Web Payment."""

    def __init__(self, session=None):
        self._session = session
        self.config = _config()

    # --- Auth -------------------------------------------------------------

    def access_token(self, *, force=False):
        """A bearer token, cached until shortly before it expires.

        Cached with a margin: a token that expires between our check and
        Orange reading it produces a 401 on a payment, which is the single
        most confusing failure this integration can have.
        """
        if not force:
            cached = cache.get(TOKEN_CACHE_KEY)
            if cached:
                return cached

        client_id = self.config.get('client_id')
        client_secret = self.config.get('client_secret')
        if not client_id or not client_secret:
            raise PaymentError('Orange Money credentials are not configured.')

        try:
            payload = request(
                'POST',
                self.config['token_url'],
                session=self._session,
                idempotent=True,
                auth=(client_id, client_secret),
                data={'grant_type': 'client_credentials'},
                headers={'Accept': 'application/json'},
            )
        except ProviderHttpError as error:
            raise PaymentError(f'Orange Money token refused: {error}') from error

        token = payload.get('access_token')
        if not token:
            raise PaymentError('Orange Money returned no access token.')

        # 60s of margin against clock skew and slow calls.
        lifetime = int(payload.get('expires_in', 3600))
        cache.set(TOKEN_CACHE_KEY, token, max(60, lifetime - 60))
        return token

    def _headers(self, token):
        return {
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        }

    # --- The interface ----------------------------------------------------

    def initiate_payment(self, subject, amount):
        """Ask Orange for a payment, and return our own order id as the key.

        The reference we keep is the `order_id` we generated, not Orange's
        `pay_token`. Both are needed to check a status, so the token is kept
        beside it in the cache — but the order id is ours, unique by
        construction, and survives Orange reissuing anything.
        """
        order_id = f'SYLI-{uuid.uuid4().hex[:16].upper()}'
        token = self.access_token()

        body = {
            'merchant_key': self.config.get('merchant_key'),
            'currency': self.config.get('currency', 'GNF'),
            'order_id': order_id,
            # Orange wants an integer number of the smallest unit. GNF has no
            # minor unit, so this is the amount as written — but it must not
            # arrive as "50000.00", which their parser reads as a string.
            'amount': int(amount),
            'return_url': self.config.get('return_url'),
            'cancel_url': self.config.get('cancel_url'),
            'notif_url': self.config.get('notif_url'),
            'lang': self.config.get('lang', 'fr'),
            'reference': self.config.get('reference', 'Sylibooking'),
        }

        try:
            payload = request(
                'POST',
                self.config['payment_url'],
                session=self._session,
                # Never retried: a repeat is a second payment request against
                # the same customer.
                idempotent=False,
                json=body,
                headers=self._headers(token),
            )
        except ProviderRefused as error:
            if error.status_code == 401:
                # The cached token went stale mid-flight. One retry with a
                # fresh one, then give up — a loop here bills nobody but
                # hides a misconfiguration.
                logger.info('Orange token rejected; refreshing once')
                token = self.access_token(force=True)
                payload = self._retry_initiate(body, token)
            else:
                raise PaymentError(
                    f'Orange Money refused the payment: {error.body}'
                ) from error
        except ProviderHttpError as error:
            raise PaymentError(f'Orange Money unreachable: {error}') from error

        pay_token = payload.get('pay_token')
        if not pay_token:
            raise PaymentError('Orange Money returned no pay_token.')

        # Kept because `transactionstatus` needs all three of order_id,
        # amount and pay_token, and only the first is on the Payment row.
        cache.set(
            _context_key(order_id),
            {
                'pay_token': pay_token,
                'amount': int(amount),
                # Orange echoes this back on the notification. Keeping it is
                # what lets the callback prove the message came from them
                # about this payment, rather than from anybody who guessed an
                # order id.
                'notif_token': payload.get('notif_token'),
            },
            60 * 60 * 24 * 7,
        )
        logger.info(
            'Orange payment initiated: order_id=%s payment_url=%s',
            order_id,
            payload.get('payment_url'),
        )
        return order_id

    def _retry_initiate(self, body, token):
        try:
            return request(
                'POST',
                self.config['payment_url'],
                session=self._session,
                idempotent=False,
                json=body,
                headers=self._headers(token),
            )
        except ProviderHttpError as error:
            raise PaymentError(
                f'Orange Money refused the payment: {error}'
            ) from error

    def check_status(self, provider_reference):
        context = cache.get(_context_key(provider_reference))
        if not context:
            # Older than the cache, or a different process. Not knowing is
            # not the same as failed, so say so and leave it pending.
            raise PaymentError(
                f'No Orange context for {provider_reference}; cannot check.'
            )

        token = self.access_token()
        try:
            payload = request(
                'POST',
                self.config['status_url'],
                session=self._session,
                # Reading a status changes nothing, so this one may repeat.
                idempotent=True,
                json={
                    'order_id': provider_reference,
                    'amount': context['amount'],
                    'pay_token': context['pay_token'],
                },
                headers=self._headers(token),
            )
        except ProviderHttpError as error:
            raise PaymentError(f'Orange status check failed: {error}') from error

        return status_from(payload.get('status'))

    def refund(self, provider_reference, amount):
        """Orange Money Web Payment has no refund endpoint.

        Said plainly rather than pretended: a merchant refunding a deposit
        does it from their Orange account, and the platform records that it
        happened. Faking success here would tell a customer their money was
        on its way when nothing had been asked of anybody.
        """
        raise PaymentError(
            'Orange Money Web Payment cannot refund from the API. Refund from '
            'the Orange merchant portal and record it here.'
        )


def context_for(order_id):
    """What was kept at initiation, or None once it has aged out."""
    return cache.get(_context_key(order_id))


def _context_key(order_id):
    return f'orange-money:context:{order_id}'


def status_from(raw):
    """Map Orange's word onto ours, defaulting to pending.

    Unknown means unknown. A status nobody has seen before is far more likely
    to be a new intermediate state than a failure, and treating it as failed
    would cancel bookings that were about to be paid for.
    """
    if raw is None:
        return Payment.Status.PENDING
    mapped = STATUS_MAP.get(str(raw).strip().upper())
    if mapped is None:
        logger.warning('Unknown Orange Money status %r; treating as pending', raw)
        return Payment.Status.PENDING
    return mapped
