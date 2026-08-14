"""Chasing payments that have not settled yet.

Until now the only thing that ever asked a provider "did this go through?"
was the customer's own screen. That works while somebody is watching it and
stops the moment they lock their phone — which is exactly when a mobile money
prompt is being approved. Against the mock that was a latency problem. Against
a real provider it is a correctness one: a paid booking that nobody noticed
stays unconfirmed, and a merchant refuses a table that was paid for.

Two rules.

**Ask less as time goes on.** A payment opened thirty seconds ago is worth
asking about every few seconds; one opened twenty minutes ago is almost
certainly never completing, and hammering the provider for it costs money and
rate limit that a fresh payment needs.

**Give up.** A payment nobody ever approved should end as failed rather than
sit pending for ever, holding a booking the merchant cannot confirm and
cannot see a reason to cancel.
"""

from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from .models import Payment


def _steps():
    """(age in minutes, how often to ask) — coarser as a payment ages."""
    return [
        (timedelta(minutes=2), timedelta(seconds=15)),
        (timedelta(minutes=10), timedelta(minutes=1)),
    ]


def poll_interval(age):
    """How long to wait between asking about a payment of this age."""
    for threshold, interval in _steps():
        if age < threshold:
            return interval
    return timedelta(minutes=5)


def abandon_after():
    return timedelta(minutes=settings.PAYMENT_ABANDON_AFTER_MINUTES)


def pending_payments():
    """Every payment still waiting on its provider.

    Deliberately not filtered to reservations: an order's payment goes stale
    in exactly the same way, and there is no reason for the two to be chased
    by different code.
    """
    return Payment.objects.filter(
        status=Payment.Status.PENDING,
    ).exclude(provider_reference='')


def due_for_poll(now=None):
    """Payments it is time to ask about again.

    Never-polled ones are always due. The rest are due once their own
    interval has passed, which depends on how old they are.
    """
    now = now or timezone.now()
    cutoff = now - abandon_after()

    due = []
    for payment in pending_payments().filter(created_at__gt=cutoff):
        if payment.last_polled_at is None:
            due.append(payment)
            continue
        age = now - payment.created_at
        if now - payment.last_polled_at >= poll_interval(age):
            due.append(payment)
    return due


def abandoned(now=None):
    """Payments old enough that nobody is going to approve them."""
    now = now or timezone.now()
    return pending_payments().filter(created_at__lte=now - abandon_after())
