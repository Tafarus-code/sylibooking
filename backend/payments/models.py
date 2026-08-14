from django.db import models
from django.utils.translation import gettext_lazy as _
from django.utils.translation import pgettext_lazy


class Payment(models.Model):
    """Money owed against a reservation, and how it is being collected.

    Only mobile money creates a Payment row today: cash on arrival is settled
    at the venue and needs nothing recorded up front. The CASH_ON_ARRIVAL
    choice exists so a merchant can log cash actually taken, once that is
    built.
    """

    class Provider(models.TextChoices):
        ORANGE_MONEY = 'orange_money', _('Orange Money')
        MTN_MONEY = 'mtn_money', _('MTN Mobile Money')
        CASH_ON_ARRIVAL = 'cash_on_arrival', _('Cash on arrival')

    class Status(models.TextChoices):
        PENDING = 'pending', pgettext_lazy('payment status', 'Pending')
        COMPLETED = 'completed', pgettext_lazy('payment status', 'Completed')
        FAILED = 'failed', pgettext_lazy('payment status', 'Failed')

    class Outcome(models.TextChoices):
        """What became of a deposit once the booking reached its end.

        A separate axis from `Status`: the payment itself stays `completed`
        whatever happens next. "Did the money arrive" and "what did we do
        with it" are different questions, and a merchant counting cash needs
        both answered.
        """

        NONE = 'none', pgettext_lazy('deposit outcome', 'Not settled yet')
        OFFSET = 'offset', pgettext_lazy(
            'deposit outcome', 'Taken off the bill'
        )
        FORFEITED = 'forfeited', pgettext_lazy(
            'deposit outcome', 'Kept for a no-show'
        )
        REFUNDED = 'refunded', pgettext_lazy('deposit outcome', 'Refunded')

    #: Providers that are settled through an external API rather than in person.
    MOBILE_MONEY_PROVIDERS = frozenset(
        {Provider.ORANGE_MONEY, Provider.MTN_MONEY}
    )

    # A payment settles exactly one thing: a table booking or a pickup order.
    # Both are nullable so either can be the one that is set, and the check
    # constraint below is what stops that becoming "neither" or "both".
    reservation = models.ForeignKey(
        'reservations.Reservation',
        on_delete=models.CASCADE,
        related_name='payments',
        null=True,
        blank=True,
        help_text='The booking this payment is for, if it is for a booking.',
    )
    order = models.ForeignKey(
        'orders.Order',
        on_delete=models.CASCADE,
        related_name='payments',
        null=True,
        blank=True,
        help_text='The pickup order this payment is for, if it is for one.',
    )
    provider = models.CharField(
        max_length=20,
        choices=Provider.choices,
        help_text='How the money is being collected.',
    )
    outcome = models.CharField(
        max_length=20,
        choices=Outcome.choices,
        default=Outcome.NONE,
        help_text=(
            'What became of the deposit once the booking ended: taken off '
            'the bill when the guests arrived, kept when they did not. Set '
            'by payments.services.settle_deposit, never by a client.'
        ),
    )
    amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        help_text=(
            'Amount in Guinean francs. Set server-side from '
            'settings.RESERVATION_DEPOSIT_AMOUNT so a client cannot choose '
            'what it owes.'
        ),
    )
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
        help_text='Updated from the provider, never by the client.',
    )
    # Nullable rather than blank-by-default: "the provider has not issued one
    # yet" is a genuinely different state from "the provider returned an empty
    # string", and only the first should ever occur. Django's usual advice
    # against null on text fields assumes those two are the same thing.
    provider_reference = models.CharField(  # noqa: DJ001
        max_length=200,
        blank=True,
        null=True,
        help_text=(
            "The provider's own id for this transaction, used to poll it "
            'later. Null until initiate_payment returns.'
        ),
    )
    last_polled_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text=(
            'When the provider was last asked about this payment. Drives the '
            'decaying poll interval — a payment opened a minute ago is worth '
            'asking about often, one opened twenty minutes ago is not.'
        ),
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['provider_reference']),
        ]
        constraints = [
            # In the database, not only in a serializer: a payment attached to
            # nothing has no one to credit, and one attached to both would be
            # counted twice in the takings.
            models.CheckConstraint(
                condition=(
                    models.Q(reservation__isnull=False, order__isnull=True)
                    | models.Q(reservation__isnull=True, order__isnull=False)
                ),
                name='payment_settles_exactly_one_thing',
            ),
        ]

    def __str__(self):
        subject = (
            f'reservation {self.reservation_id}'
            if self.reservation_id
            else f'order {self.order_id}'
        )
        return (
            f'{self.get_provider_display()} {self.amount} '
            f'({self.get_status_display()}) for {subject}'
        )

    @property
    def is_mobile_money(self):
        return self.provider in self.MOBILE_MONEY_PROVIDERS
