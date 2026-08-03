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
    return _start(
        provider_name,
        amount=deposit_amount() if amount is None else amount,
        reservation=reservation,
    )


def start_order_payment(order, provider_name):
    """Open a payment for a pickup order.

    The amount is the order's own total rather than the global deposit: the
    customer is buying named dishes at snapshotted prices, so what is owed is
    already decided and is not ours to choose.

    Cash on pickup writes no Payment row, exactly as cash on arrival does not.
    """
    return _start(provider_name, amount=order.total, order=order)


def _start(provider_name, *, amount, reservation=None, order=None):
    """The shared body: create, initiate, then apply whatever came back."""
    if provider_name == Payment.Provider.CASH_ON_ARRIVAL:
        return None

    subject = reservation if reservation is not None else order

    payment = Payment.objects.create(
        reservation=reservation,
        order=order,
        provider=provider_name,
        amount=amount,
        status=Payment.Status.PENDING,
    )

    try:
        provider = get_payment_provider(provider_name)
        payment.provider_reference = provider.initiate_payment(
            subject, payment.amount
        )
        payment.save(update_fields=['provider_reference'])
    except PaymentError:
        # We could not place the request, so nothing is owed and nothing was
        # taken. Mark it failed and leave the booking pending.
        logger.exception(
            'Could not initiate %s payment for %s %s',
            provider_name,
            type(subject).__name__.lower(),
            subject.pk,
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

    if status == Payment.Status.COMPLETED and payment.reservation_id:
        # An order needs no equivalent: paying does not advance it through the
        # kitchen, it only unblocks the merchant from doing so.
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


def settle_deposit(reservation):
    """Decide what became of a booking's deposit, now that the booking ended.

    D1: a deposit is taken off the bill when the guests arrive, and kept when
    they do not. The customer is told both before they book — a forfeiture the
    customer did not see coming is a dispute, not a policy.

    Which of the two applies is read off the booking's own status, and that
    status was reached using the grace period captured *on the booking* when
    it was taken. So a venue that shortens its window on Tuesday cannot
    thereby keep money taken on Monday under longer terms; the question was
    already settled by the time this runs.

    Idempotent: a deposit that already has an outcome keeps it. The lapse
    sweep will run constantly once it is on a scheduler, and settling twice
    must not turn one no-show into two forfeits in the takings.

    Returns the Payment it settled, or None when there was nothing to settle —
    a cash booking, or one whose payment never completed.
    """
    payment = (
        reservation.payments.filter(status=Payment.Status.COMPLETED)
        .order_by('-created_at')
        .first()
    )
    if payment is None:
        # Cash on arrival, or money that never arrived. Nothing was taken, so
        # there is nothing to keep or give back.
        return None

    if payment.outcome != Payment.Outcome.NONE:
        return payment

    if reservation.status == Reservation.Status.COMPLETED:
        payment.outcome = Payment.Outcome.OFFSET
    elif reservation.status == Reservation.Status.NO_SHOW:
        payment.outcome = Payment.Outcome.FORFEITED
    else:
        # Still open, or cancelled. Cancellation has its own rules and is not
        # this function's to invent.
        return payment

    payment.save(update_fields=['outcome'])
    logger.info(
        'Deposit %s on reservation %s settled as %s',
        payment.provider_reference,
        reservation.pk,
        payment.outcome,
    )
    return payment


def refund_deposit(payment):
    """Give a deposit back through the provider that took it.

    Nothing calls this yet — the mock is the only implementation until the
    Orange Money slice. It exists now so that slice is an adapter and not an
    interface change, and so the outcome it writes is already understood by
    the dashboard.
    """
    if payment.outcome == Payment.Outcome.REFUNDED:
        return payment

    provider = get_payment_provider(payment.provider)
    provider.refund(payment.provider_reference, payment.amount)

    payment.outcome = Payment.Outcome.REFUNDED
    payment.save(update_fields=['outcome'])
    return payment


def latest_payment_for(subject):
    """The payment a customer would be asking about — the most recent one.

    Takes a reservation or an order; both expose the same `payments` relation.
    """
    return subject.payments.order_by('-created_at').first()
