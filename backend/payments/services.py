"""The payment flow around a reservation.

Kept out of the views so the merchant app, the customer app and the admin all
get the same rules — above all the one that matters: a reservation becomes
confirmed only when its payment has actually completed.
"""

import logging

from django.conf import settings
from django.db import transaction

from reservations.models import Reservation

from .models import Payment
from .providers import PaymentError, get_payment_provider

logger = logging.getLogger(__name__)


def deposit_amount():
    """What a mobile money booking costs up front.

    One global figure for now. Per-establishment pricing is a real product
    decision — it belongs on Establishment, not in a client request, since a
    client must never choose what it owes.
    """
    return settings.RESERVATION_DEPOSIT_AMOUNT


def start_payment(reservation, provider_name, amount=None):
    """Open a payment for `reservation` and sync the booking to its outcome.

    Cash on arrival is not a payment as far as this module is concerned: there
    is nothing to collect now, so no Payment row is written and the booking
    stays pending for the merchant to confirm by hand, exactly as before.

    Returns the Payment, or None for cash on arrival.
    """
    if provider_name == Payment.Provider.CASH_ON_ARRIVAL:
        return None

    payment = Payment.objects.create(
        reservation=reservation,
        provider=provider_name,
        amount=deposit_amount() if amount is None else amount,
        status=Payment.Status.PENDING,
    )

    try:
        provider = get_payment_provider(provider_name)
        payment.provider_reference = provider.initiate_payment(
            reservation, payment.amount
        )
        payment.save(update_fields=['provider_reference'])
    except PaymentError:
        # We could not place the request, so nothing is owed and nothing was
        # taken. Mark it failed and leave the booking pending.
        logger.exception(
            'Could not initiate %s payment for reservation %s',
            provider_name,
            reservation.pk,
        )
        payment.status = Payment.Status.FAILED
        payment.save(update_fields=['status'])
        return payment

    refresh_payment(payment)
    return payment


def refresh_payment(payment):
    """Ask the provider where the payment stands, and apply the consequences.

    Safe to call repeatedly — polling is how a customer's app finds out that a
    payment went through.
    """
    if payment.status == Payment.Status.COMPLETED:
        # Terminal and already applied; asking again cannot change it.
        return payment

    if not payment.provider_reference:
        return payment

    try:
        provider = get_payment_provider(payment.provider)
        status = provider.check_status(payment.provider_reference)
    except PaymentError:
        # Unreachable is not the same as failed: leave it pending so the next
        # poll can settle it, rather than telling the customer it went wrong.
        logger.exception(
            'Could not check %s payment %s',
            payment.provider,
            payment.provider_reference,
        )
        return payment

    if status == payment.status:
        return payment

    payment.status = status
    payment.save(update_fields=['status'])

    if status == Payment.Status.COMPLETED:
        confirm_reservation_for(payment)

    return payment


def confirm_reservation_for(payment):
    """Move the booking to confirmed now that it is paid.

    Deliberately narrow: a cancelled or completed booking is left alone. A
    late payment landing against a booking the customer already cancelled must
    not quietly reinstate the table.
    """
    with transaction.atomic():
        reservation = Reservation.objects.select_for_update().get(
            pk=payment.reservation_id
        )
        if reservation.status != Reservation.Status.PENDING:
            logger.info(
                'Payment %s completed but reservation %s is %s; leaving it.',
                payment.provider_reference,
                reservation.pk,
                reservation.status,
            )
            return reservation

        reservation.status = Reservation.Status.CONFIRMED
        reservation.save(update_fields=['status'])
        return reservation


def latest_payment_for(reservation):
    """The payment a customer would be asking about — the most recent one."""
    return reservation.payments.order_by('-created_at').first()
