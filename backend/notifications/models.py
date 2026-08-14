"""A record of every message this system tried to send.

Without this, "did the customer get the reminder?" has no answer — and it is
the first question a merchant asks when someone does not turn up. A row is
written whether the send worked or not, because a failure nobody recorded is
indistinguishable from a message nobody sent.

The unique constraints are doing real work. A scheduler fires repeatedly and
a worker can be restarted mid-task, so "send this once" has to be a fact
about the database rather than a hope about timing.
"""

from django.db import models
from django.utils import timezone


class Notification(models.Model):
    """One attempt to tell somebody something."""

    class Kind(models.TextChoices):
        BOOKING_REMINDER = 'booking_reminder', 'Booking reminder'
        ORDER_READY = 'order_ready', 'Order ready'

    class Channel(models.TextChoices):
        SMS = 'sms', 'SMS'
        EMAIL = 'email', 'Email'

    class Status(models.TextChoices):
        SENT = 'sent', 'Sent'
        FAILED = 'failed', 'Failed'

    kind = models.CharField(max_length=32, choices=Kind.choices)
    channel = models.CharField(
        max_length=16,
        choices=Channel.choices,
        default=Channel.SMS,
    )

    # What it was about. Exactly one of these is set — the same shape Payment
    # uses, for the same reason.
    reservation = models.ForeignKey(
        'reservations.Reservation',
        on_delete=models.CASCADE,
        related_name='notifications',
        null=True,
        blank=True,
    )
    order = models.ForeignKey(
        'orders.Order',
        on_delete=models.CASCADE,
        related_name='notifications',
        null=True,
        blank=True,
    )

    destination = models.CharField(
        max_length=200,
        help_text='The number or address it was sent to.',
    )
    status = models.CharField(max_length=16, choices=Status.choices)
    error = models.TextField(
        blank=True,
        default='',
        help_text='Why it failed, when it did. Empty on success.',
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ['-created_at']
        constraints = [
            # One reminder per booking, one ready-message per order. Enforced
            # here rather than by checking first: two workers can check at the
            # same moment and both find nothing.
            models.UniqueConstraint(
                fields=['kind', 'reservation'],
                condition=models.Q(reservation__isnull=False),
                name='one_notification_per_kind_per_reservation',
            ),
            models.UniqueConstraint(
                fields=['kind', 'order'],
                condition=models.Q(order__isnull=False),
                name='one_notification_per_kind_per_order',
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(reservation__isnull=False, order__isnull=True)
                    | models.Q(reservation__isnull=True, order__isnull=False)
                ),
                name='notification_is_about_exactly_one_thing',
            ),
        ]

    def __str__(self):
        return f'{self.get_kind_display()} → {self.destination} ({self.status})'


# Push tokens live in their own module for readability; imported here so
# Django's app registry finds them where it expects to.
from .devices import DeviceToken  # noqa: E402,F401
