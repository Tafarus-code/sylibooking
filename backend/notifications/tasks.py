"""Work that happens away from a request.

Tasks live in their own app rather than accreting inside `api/`: they are not
endpoints, they outlive the request that queued them, and mixing the two makes
it hard to see what actually runs on a worker.

Two rules everything here follows.

A task takes ids, not objects. The row may have changed between queueing and
running — that gap is the whole point of a queue — so a task re-reads what it
needs and decides then. A booking cancelled in the meantime gets no reminder.

A task that cannot do its job says so by raising, and lets the retry policy
decide. Swallowing the error means a reminder that never arrives and nothing
anywhere recording that it did not.
"""

import logging

from accounts.notifications import NotificationError, get_notifier
from celery import shared_task
from django.db import IntegrityError, transaction

from .models import Notification

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    max_retries=3,
    default_retry_delay=30,
    autoretry_for=(Exception,),
    retry_backoff=True,
)
def send_test_notification(self, message='ping'):
    """Prove the wiring, and nothing else.

    Kept from the slice that introduced the queue: it is how you check a
    worker is alive without waiting for a real booking to come due.
    """
    logger.info('Task queue reached: %s', message)
    return message


def _claim(kind, *, reservation=None, order=None, destination, channel):
    """Take the one slot for this notification, or return None.

    The unique constraint is the lock. Two workers racing both try to insert,
    one loses, and the loser sends nothing — which is what stops a scheduler
    that fires twice from sending twice.

    The row is written *before* the message goes out, so a worker that dies
    mid-send leaves a record rather than silently retrying for ever. Its
    status is corrected once the outcome is known.
    """
    try:
        with transaction.atomic():
            return Notification.objects.create(
                kind=kind,
                channel=channel,
                reservation=reservation,
                order=order,
                destination=destination,
                status=Notification.Status.FAILED,
                error='not attempted yet',
            )
    except IntegrityError:
        return None


@shared_task(
    bind=True,
    max_retries=3,
    default_retry_delay=60,
    retry_backoff=True,
)
def send_booking_reminder(self, reservation_id):
    """Tell one customer their table is coming up.

    Re-reads the booking rather than trusting what was queued: a table
    cancelled between queueing and running must not be reminded about.
    """
    from reservations.models import Reservation

    from .reminders import reminder_text

    try:
        reservation = Reservation.objects.select_related(
            'space__establishment'
        ).get(pk=reservation_id)
    except Reservation.DoesNotExist:
        # Deleted between queueing and running. Nothing to do, and nothing
        # wrong: retrying cannot bring it back.
        return 'gone'

    if reservation.status not in Reservation.OPEN_STATUSES:
        return 'not open'
    if not reservation.customer_phone:
        return 'no destination'

    notification = _claim(
        Notification.Kind.BOOKING_REMINDER,
        reservation=reservation,
        destination=reservation.customer_phone,
        channel=Notification.Channel.SMS,
    )
    if notification is None:
        # Somebody else already has this one.
        return 'already sent'

    try:
        get_notifier('sms').send(
            destination=reservation.customer_phone,
            subject='Booking reminder',
            body=reminder_text(reservation),
        )
    except NotificationError as error:
        notification.error = str(error)
        notification.save(update_fields=['error'])
        # Retry: the gateway may be back in a minute. The row stays, marked
        # failed, so a merchant can see the attempt either way.
        raise self.retry(exc=error) from error

    notification.status = Notification.Status.SENT
    notification.error = ''
    notification.save(update_fields=['status', 'error'])
    return 'sent'


@shared_task(
    bind=True,
    max_retries=3,
    default_retry_delay=60,
    retry_backoff=True,
)
def send_order_ready(self, order_id):
    """Tell one customer their food is on the counter."""
    from orders.models import Order

    try:
        order = Order.objects.select_related('establishment').get(pk=order_id)
    except Order.DoesNotExist:
        return 'gone'

    if not order.customer_phone:
        return 'no destination'

    notification = _claim(
        Notification.Kind.ORDER_READY,
        order=order,
        destination=order.customer_phone,
        channel=Notification.Channel.SMS,
    )
    if notification is None:
        return 'already sent'

    body = (
        f'Your order at {order.establishment.name} is ready to collect.'
    )
    try:
        get_notifier('sms').send(
            destination=order.customer_phone,
            subject='Order ready',
            body=body,
        )
    except NotificationError as error:
        notification.error = str(error)
        notification.save(update_fields=['error'])
        raise self.retry(exc=error) from error

    notification.status = Notification.Status.SENT
    notification.error = ''
    notification.save(update_fields=['status', 'error'])
    return 'sent'


@shared_task
def queue_due_reminders():
    """Find bookings whose reminder is due and hand each to its own task.

    Split in two on purpose: this one is cheap and runs often, and one
    customer's gateway failure retries on its own without holding up
    everybody else's reminder.
    """
    from .reminders import due_reservations

    due = due_reservations()
    for reservation in due:
        send_booking_reminder.delay(reservation.pk)
    return len(due)


@shared_task
def sweep_no_shows():
    """Close out bookings nobody turned up for, on a schedule.

    The same rule the management command runs, moved onto the scheduler as
    Slice 4 said it would be. The command stays: it is how you run this by
    hand, and how you see what it would do with --dry-run.
    """
    from django.core.management import call_command

    call_command('lapse_no_shows', verbosity=0)
