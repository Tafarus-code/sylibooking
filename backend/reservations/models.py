import uuid
from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone
from django.utils.translation import pgettext_lazy

from establishments.models import Space

from .no_show import no_show_window


class Reservation(models.Model):
    """A customer holding a space at a given date and time.

    Payment is "pay on arrival" for now — deposit and payment status fields
    arrive with the payments app.
    """

    class Status(models.TextChoices):
        PENDING = 'pending', pgettext_lazy('reservation status', 'Pending')
        CONFIRMED = 'confirmed', pgettext_lazy('reservation status', 'Confirmed')
        CANCELLED = 'cancelled', pgettext_lazy('reservation status', 'Cancelled')
        COMPLETED = 'completed', pgettext_lazy('reservation status', 'Completed')
        NO_SHOW = 'no_show', pgettext_lazy('reservation status', 'Missed')

    #: Statuses a booking can still move on from.
    OPEN_STATUSES = frozenset({Status.PENDING, Status.CONFIRMED})

    reference = models.UUIDField(
        default=uuid.uuid4,
        unique=True,
        editable=False,
        db_index=True,
        help_text=(
            'Unguessable handle the customer uses to view or cancel their own '
            'booking. Customers have no accounts, so this is what proves the '
            'booking is theirs — the sequential id must not be used for that.'
        ),
    )
    space = models.ForeignKey(
        Space,
        on_delete=models.PROTECT,
        related_name='reservations',
        help_text='The table or room being held.',
    )
    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reservations',
        help_text=(
            'The account this booking belongs to, once there is one. Null for '
            'the account-less path, which stays the default — the reference is '
            'what proves ownership either way.'
        ),
    )
    customer_name = models.CharField(
        max_length=200,
        help_text='Name the booking is under.',
    )
    customer_phone = models.CharField(
        max_length=30,
        help_text='Phone number for confirmation/reminder, e.g. "+224 620 00 00 00".',
    )
    datetime = models.DateTimeField(
        help_text='Start of the reservation.',
    )
    party_size = models.PositiveSmallIntegerField(
        help_text='Number of guests expected.',
    )
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
        help_text=(
            'Merchant confirms or cancels; completed is set when the guests '
            'arrive, and missed when the grace period passes without them.'
        ),
    )
    arrived_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text='When the merchant marked the guests as arrived.',
    )
    no_show_after_minutes = models.PositiveSmallIntegerField(
        null=True,
        blank=True,
        help_text=(
            'The grace period this booking was taken under, copied from the '
            'venue when it was made. Deliberately not read live: the customer '
            'is told this figure before they book, and shortening the venue’s '
            'window afterwards must not retroactively make them a no-show — '
            'or forfeit a deposit taken under longer terms.'
        ),
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-datetime']

    def __str__(self):
        return (
            f'{self.customer_name} — {self.space.name} '
            f'@ {self.datetime:%Y-%m-%d %H:%M} ({self.get_status_display()})'
        )

    def save(self, *args, **kwargs):
        """Capture the grace period the first time this booking is written.

        Done here rather than in the serializer so every path agrees — the
        API, the admin, seed data and tests all take a booking under the terms
        that were current when they took it.
        """
        if self._state.adding and self.no_show_after_minutes is None:
            self.no_show_after_minutes = no_show_window(
                self.space.establishment
            )
        super().save(*args, **kwargs)

    @property
    def no_show_deadline(self):
        """When this booking stops being held. None if it was never captured.

        Only bookings written before this field existed can be None; they are
        left alone by the sweep rather than judged under today's rules.
        """
        if self.no_show_after_minutes is None:
            return None
        return self.datetime + timedelta(minutes=self.no_show_after_minutes)

    @property
    def has_started(self):
        return self.datetime <= timezone.now()

    @property
    def latest_payment(self):
        """The payment this booking is settled by, if any.

        Cash on arrival writes no Payment row, so this is None for those —
        which is what tells the merchant list to show "Cash on arrival"
        rather than "Unpaid".
        """
        # Uses the prefetched list when the caller prefetched, so a day's
        # worth of bookings does not become a query per row.
        payments = self.payments.all()
        return max(payments, key=lambda p: p.created_at, default=None)

    @property
    def payment_provider(self):
        """How this booking is being paid, cash included."""
        payment = self.latest_payment
        if payment is None:
            # Imported here: payments depends on reservations, not the reverse.
            from payments.models import Payment

            return Payment.Provider.CASH_ON_ARRIVAL
        return payment.provider

    @property
    def payment_status(self):
        """Status of the payment, or None when there is nothing to settle."""
        payment = self.latest_payment
        return None if payment is None else payment.status

    @property
    def is_paid(self):
        from payments.models import Payment

        payment = self.latest_payment
        return payment is not None and payment.status == Payment.Status.COMPLETED

    @property
    def needs_payment_before_confirming(self):
        """True when money must arrive before the merchant may confirm.

        Cash on arrival is confirmed on trust — that is the whole point of it.
        A mobile money booking that has not been paid is a different thing:
        confirming it would hold a table against money that never came.
        """
        from payments.models import Payment

        payment = self.latest_payment
        if payment is None:
            return False
        return payment.is_mobile_money and payment.status != Payment.Status.COMPLETED

    def customer_cancellable_reason(self):
        """Why the customer may not cancel this, or None if they may.

        A merchant can cancel more freely — they are in the room and can see
        what actually happened. A customer cancelling a visit that already
        began would be rewriting history, so those get sent to the venue.
        """
        if self.status == self.Status.COMPLETED:
            return 'This visit already happened.'
        if self.status == self.Status.CANCELLED:
            return None  # Already cancelled; cancelling again is a no-op.
        if self.has_started:
            return (
                'This booking has already started. Please call the venue '
                'directly.'
            )
        return None