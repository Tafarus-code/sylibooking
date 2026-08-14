"""Where the providers tell us a payment moved.

Polling already settles every payment eventually — `poll_pending_payments`
runs every 30 seconds — so these endpoints are not load-bearing. What they buy
is the difference between a customer waiting half a minute and waiting not at
all, which on a phone with a payment prompt still open is most of the
experience.

Four rules, and every one of them exists because this is the only unauthenticated
write surface in the product.

**The payload is untrusted.** It says a payment succeeded; anybody can say
that. Nothing here believes an amount, a status or an id without asking the
provider — the notification is a nudge to go and check, never the answer
itself. That single decision removes most of what could be done with a forged
callback.

**A shared secret guards the path.** A notification URL that anybody can find
is a notification URL anybody can post to, so the configured URL carries a
secret and a request without it is refused before anything is parsed.

**Twice is once.** Providers redeliver, sometimes for hours. Applying a
callback is `refresh_payment`, which is idempotent by construction, so a
duplicate does nothing at all.

**Answer 200 quickly, even when confused.** A provider that gets an error
retries harder, and a retry storm against a payment we already have is worse
than a shrug. Anything unexpected is logged loudly and acknowledged.
"""

import hmac
import logging

from django.conf import settings
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from payments.models import Payment
from payments.orange import context_for
from payments.services import refresh_payment

logger = logging.getLogger(__name__)


def _secret_ok(supplied, configured):
    """Constant-time compare, and never true when nothing is configured.

    An empty configured secret must not mean "everything matches" — that is
    how a callback endpoint ends up open in production because an environment
    variable was spelled wrong.
    """
    if not configured:
        logger.error('A payment callback secret is not configured; refusing.')
        return False
    return hmac.compare_digest(str(supplied or ''), str(configured))


class _CallbackView(APIView):
    """Shared plumbing: no auth, no throttle, and a fast 200."""

    authentication_classes = []
    permission_classes = [AllowAny]
    # Deliberately unthrottled. A provider redelivering hard is exactly when
    # we most want to hear them, and the work behind this is one cheap lookup
    # plus a status check that is itself rate-limited by the provider.
    throttle_classes = []

    def acknowledge(self, note=None):
        if note:
            logger.info('payment callback: %s', note)
        return Response({'received': True}, status=status.HTTP_200_OK)


class OrangeMoneyCallbackView(_CallbackView):
    """POST /api/payments/callbacks/orange/<secret>/

    Orange posts `order_id`, `status` and the `notif_token` it issued when the
    payment was created. The token is checked against what we kept, which is
    what proves this message is about this payment.
    """

    def post(self, request, secret):
        if not _secret_ok(secret, getattr(settings, 'ORANGE_CALLBACK_SECRET', '')):
            return Response(status=status.HTTP_404_NOT_FOUND)

        order_id = str(request.data.get('order_id') or '').strip()
        if not order_id:
            return self.acknowledge('Orange callback with no order_id')

        context = context_for(order_id)
        expected = (context or {}).get('notif_token')
        if expected and not _secret_ok(request.data.get('notif_token'), expected):
            # Someone knows an order id but not the token. Worth shouting
            # about: it is the only signal we would ever get that somebody is
            # probing this endpoint.
            logger.error(
                'Orange callback for %s carried the wrong notif_token', order_id
            )
            return Response(status=status.HTTP_403_FORBIDDEN)

        payment = Payment.objects.filter(provider_reference=order_id).first()
        if payment is None:
            return self.acknowledge(f'Orange callback for unknown order {order_id}')

        # The payload's own status is deliberately ignored. We go and ask.
        refresh_payment(payment)
        return self.acknowledge()


class MtnMoneyCallbackView(_CallbackView):
    """POST /api/payments/callbacks/mtn/<secret>/

    MTN posts the transaction it is telling us about; the reference is the
    `X-Reference-Id` we generated, which is already the row's
    `provider_reference`.
    """

    def post(self, request, secret):
        if not _secret_ok(secret, getattr(settings, 'MTN_CALLBACK_SECRET', '')):
            return Response(status=status.HTTP_404_NOT_FOUND)

        reference = str(
            request.data.get('referenceId')
            or request.data.get('externalId')
            or request.headers.get('X-Reference-Id')
            or ''
        ).strip()
        if not reference:
            return self.acknowledge('MTN callback with no reference')

        payment = Payment.objects.filter(provider_reference=reference).first()
        if payment is None:
            return self.acknowledge(f'MTN callback for unknown payment {reference}')

        refresh_payment(payment)
        return self.acknowledge()
