"""MTN Mobile Money, against the Collections API.

MTN's shape is different from Orange's in one way that matters: **we choose
the transaction id**. `X-Reference-Id` is a UUID we generate and send, and it
is both the idempotency key and the handle for every later question about the
payment. That makes MTN the easier of the two to reason about — a retry with
the same id is the same transaction, not a second one.

The customer authorises on their handset after a `requesttopay`, exactly as
with Orange, so the flow above this file is identical.

**Endpoints and the subscription key are settings.** The sandbox and
production hosts differ, and the target environment string ("sandbox" or
"mtnguinea") is part of the contract MTN issues you. This was written from
the published shape; check it against your account when the credentials
arrive and change settings, not code.
"""

import logging
import uuid

from django.conf import settings
from django.core.cache import cache

from .http import ProviderHttpError, ProviderRefused, request
from .models import Payment
from .providers import PaymentError, PaymentProvider

logger = logging.getLogger(__name__)

#: MTN's vocabulary. PENDING is the state a customer is in while their phone
#: is asking them to approve, which is most of the life of a payment.
STATUS_MAP = {
    'SUCCESSFUL': Payment.Status.COMPLETED,
    'PENDING': Payment.Status.PENDING,
    'FAILED': Payment.Status.FAILED,
    'REJECTED': Payment.Status.FAILED,
    'TIMEOUT': Payment.Status.FAILED,
    'EXPIRED': Payment.Status.FAILED,
}

TOKEN_CACHE_KEY = 'mtn-momo:access-token'


def _config():
    return getattr(settings, 'MTN_MOMO', {})


def msisdn(phone):
    """A number MTN will accept: digits only, no plus, no spaces.

    A customer types `+224 620 00 00 00` and MTN wants `224620000000`. Doing
    this in one place stops each call site inventing its own version of
    "clean the number", which is how one of them ends up wrong.
    """
    return ''.join(character for character in (phone or '') if character.isdigit())


class MtnMoneyProvider(PaymentProvider):
    """MTN MoMo Collections."""

    def __init__(self, session=None):
        self._session = session
        self.config = _config()

    # --- Auth -------------------------------------------------------------

    def access_token(self, *, force=False):
        if not force:
            cached = cache.get(TOKEN_CACHE_KEY)
            if cached:
                return cached

        api_user = self.config.get('api_user')
        api_key = self.config.get('api_key')
        subscription_key = self.config.get('subscription_key')
        if not (api_user and api_key and subscription_key):
            raise PaymentError('MTN MoMo credentials are not configured.')

        try:
            payload = request(
                'POST',
                f"{self.config['base_url']}/collection/token/",
                session=self._session,
                idempotent=True,
                auth=(api_user, api_key),
                headers={
                    'Ocp-Apim-Subscription-Key': subscription_key,
                    'Accept': 'application/json',
                },
            )
        except ProviderHttpError as error:
            raise PaymentError(f'MTN token refused: {error}') from error

        token = payload.get('access_token')
        if not token:
            raise PaymentError('MTN returned no access token.')

        lifetime = int(payload.get('expires_in', 3600))
        cache.set(TOKEN_CACHE_KEY, token, max(60, lifetime - 60))
        return token

    def _headers(self, token, *, reference=None):
        headers = {
            'Authorization': f'Bearer {token}',
            'X-Target-Environment': self.config.get('environment', 'sandbox'),
            'Ocp-Apim-Subscription-Key': self.config['subscription_key'],
            'Content-Type': 'application/json',
        }
        if reference:
            headers['X-Reference-Id'] = reference
        return headers

    # --- The interface ----------------------------------------------------

    def initiate_payment(self, subject, amount):
        """Ask the customer's handset to approve a payment.

        The reference is generated here and sent as `X-Reference-Id`, so it
        is ours, unique, and the same value MTN answers about later. MTN
        replies 202 with an empty body: acceptance of the request, not of the
        money. Everything after that is a status check.
        """
        reference = str(uuid.uuid4())
        token = self.access_token()
        payer = msisdn(getattr(subject, 'customer_phone', ''))
        if not payer:
            raise PaymentError('No phone number to charge.')

        body = {
            'amount': str(int(amount)),
            'currency': self.config.get('currency', 'GNF'),
            # Our own id for their statement. The booking reference is the
            # thing a merchant will be asked about when this is disputed.
            'externalId': str(getattr(subject, 'reference', subject.pk)),
            'payer': {'partyIdType': 'MSISDN', 'partyId': payer},
            'payerMessage': self.config.get('payer_message', 'Sylibooking'),
            'payeeNote': self.config.get('payee_note', 'Sylibooking booking'),
        }

        try:
            request(
                'POST',
                f"{self.config['base_url']}/collection/v1_0/requesttopay",
                session=self._session,
                # Never retried here even though X-Reference-Id makes it safe:
                # our own retry would race MTN's processing of the first, and
                # the poller will settle it either way.
                idempotent=False,
                json=body,
                headers=self._headers(token, reference=reference),
            )
        except ProviderRefused as error:
            raise PaymentError(
                f'MTN refused the payment request: {error.body}'
            ) from error
        except ProviderHttpError as error:
            raise PaymentError(f'MTN unreachable: {error}') from error

        logger.info('MTN payment requested: reference=%s payer=%s', reference, payer)
        return reference

    def check_status(self, provider_reference):
        token = self.access_token()
        try:
            payload = request(
                'GET',
                f"{self.config['base_url']}/collection/v1_0/requesttopay/"
                f'{provider_reference}',
                session=self._session,
                idempotent=True,
                headers=self._headers(token),
            )
        except ProviderHttpError as error:
            raise PaymentError(f'MTN status check failed: {error}') from error

        return status_from(payload.get('status'))

    def refund(self, provider_reference, amount):
        """Give a completed collection back, through Disbursements.

        A different product with its own subscription key, which is why this
        can be configured off independently: a venue may be collecting long
        before anybody has arranged disbursements.
        """
        disbursement_key = self.config.get('disbursement_subscription_key')
        if not disbursement_key:
            raise PaymentError(
                'MTN refunds need a disbursement subscription key, which is '
                'not configured.'
            )

        token = self.access_token()
        reference = str(uuid.uuid4())
        try:
            request(
                'POST',
                f"{self.config['base_url']}/disbursement/v1_0/refund",
                session=self._session,
                idempotent=False,
                json={
                    'amount': str(int(amount)),
                    'currency': self.config.get('currency', 'GNF'),
                    'externalId': provider_reference,
                    'referenceIdToRefund': provider_reference,
                    'payerMessage': 'Sylibooking refund',
                    'payeeNote': 'Sylibooking refund',
                },
                headers={
                    **self._headers(token, reference=reference),
                    'Ocp-Apim-Subscription-Key': disbursement_key,
                },
            )
        except ProviderHttpError as error:
            raise PaymentError(f'MTN refund failed: {error}') from error

        logger.info('MTN refund requested: %s', reference)
        return True


def status_from(raw):
    """Map MTN's word onto ours, defaulting to pending.

    Same rule as Orange: unknown is pending, never failed. A status nobody
    has seen is more likely a new intermediate state than a lost payment.
    """
    if raw is None:
        return Payment.Status.PENDING
    mapped = STATUS_MAP.get(str(raw).strip().upper())
    if mapped is None:
        logger.warning('Unknown MTN status %r; treating as pending', raw)
        return Payment.Status.PENDING
    return mapped
