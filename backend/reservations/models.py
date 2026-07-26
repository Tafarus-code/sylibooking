from django.db import models

from establishments.models import Space


class Reservation(models.Model):
    """A customer holding a space at a given date and time.

    Payment is "pay on arrival" for now — deposit and payment status fields
    arrive with the payments app.
    """

    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        CONFIRMED = 'confirmed', 'Confirmed'
        CANCELLED = 'cancelled', 'Cancelled'
        COMPLETED = 'completed', 'Completed'

    space = models.ForeignKey(
        Space,
        on_delete=models.PROTECT,
        related_name='reservations',
        help_text='The table or room being held.',
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
        help_text='Merchant confirms or cancels; completed is set after the visit.',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-datetime']

    def __str__(self):
        return (
            f'{self.customer_name} — {self.space.name} '
            f'@ {self.datetime:%Y-%m-%d %H:%M} ({self.get_status_display()})'
        )