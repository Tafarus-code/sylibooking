from django.db import models


class Payment(models.Model):
    """Money owed against a reservation, and how it is being collected.

    Only mobile money creates a Payment row today: cash on arrival is settled
    at the venue and needs nothing recorded up front. The CASH_ON_ARRIVAL
    choice exists so a merchant can log cash actually taken, once that is
    built.
    """

    class Provider(models.TextChoices):
        ORANGE_MONEY = 'orange_money', 'Orange Money'
        MTN_MONEY = 'mtn_money', 'MTN Mobile Money'
        CASH_ON_ARRIVAL = 'cash_on_arrival', 'Cash on arrival'

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        COMPLETED = 'completed', 'Completed'
        FAILED = 'failed', 'Failed'

    #: Providers that are settled through an external API rather than in person.
    MOBILE_MONEY_PROVIDERS = frozenset(
        {Provider.ORANGE_MONEY, Provider.MTN_MONEY}
    )

    reservation = models.ForeignKey(
        'reservations.Reservation',
        on_delete=models.CASCADE,
        related_name='payments',
        help_text='The booking this payment is for.',
    )
    provider = models.CharField(
        max_length=20,
        choices=Provider.choices,
        help_text='How the money is being collected.',
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
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['provider_reference']),
        ]

    def __str__(self):
        return (
            f'{self.get_provider_display()} {self.amount} '
            f'({self.get_status_display()}) for reservation '
            f'{self.reservation_id}'
        )

    @property
    def is_mobile_money(self):
        return self.provider in self.MOBILE_MONEY_PROVIDERS
