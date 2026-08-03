"""Payment provider adapters.

One interface, so the reservation flow never learns whether it is talking to
Orange Money, MTN, or the mock. Real providers land behind this same interface
once the flow is proven; nothing above this module should change when they do.
"""

import logging
import uuid
from abc import ABC, abstractmethod

from django.conf import settings
from django.utils.module_loading import import_string

from .models import Payment

logger = logging.getLogger(__name__)


class PaymentError(Exception):
    """The provider could not be reached, or refused the request.

    Distinct from a payment that legitimately failed: this means we do not
    know the outcome.
    """


class PaymentProvider(ABC):
    """What every mobile money integration must offer."""

    @abstractmethod
    def initiate_payment(self, reservation, amount):
        """Start a payment and return the provider's reference for it.

        The reference is what `check_status` is later called with, so it must
        be stable and unique. Raise `PaymentError` if the request could not be
        placed at all.
        """

    @abstractmethod
    def check_status(self, provider_reference):
        """Return one of `Payment.Status` for an existing transaction."""

    @abstractmethod
    def refund(self, provider_reference, amount):
        """Give a completed payment back.

        On the interface before there is a real provider to implement it, so
        that adding one is an adapter rather than an interface change — and
        so the deposit rules can be written against a complete picture of
        what can happen to money.

        Raise `PaymentError` if the request could not be placed at all.
        """


class MockPaymentProvider(PaymentProvider):
    """Always succeeds, immediately.

    This is what the reservation flow is built and demonstrated against, so
    the whole loop can be exercised without a provider sandbox. It records
    what it was asked to do in the log, which is the closest thing to a
    receipt at this stage.
    """

    prefix = 'MOCK'

    def initiate_payment(self, reservation, amount):
        reference = f'{self.prefix}-{uuid.uuid4().hex[:16].upper()}'
        logger.info(
            'Mock payment initiated: %s for reservation %s, amount %s',
            reference,
            reservation.pk,
            amount,
        )
        return reference

    def check_status(self, provider_reference):
        logger.info('Mock payment %s reported completed', provider_reference)
        return Payment.Status.COMPLETED

    def refund(self, provider_reference, amount):
        logger.info(
            'Mock refund of %s against payment %s', amount, provider_reference
        )
        return True


def get_payment_provider(provider_name):
    """Return the adapter configured for `provider_name`.

    Which class serves which provider is a settings decision, so swapping the
    mock for a real integration is configuration rather than a code change.
    """
    backends = getattr(settings, 'PAYMENT_PROVIDERS', {})
    try:
        dotted_path = backends[provider_name]
    except KeyError:
        raise PaymentError(
            f'No payment provider configured for {provider_name!r}.'
        ) from None

    return import_string(dotted_path)()
