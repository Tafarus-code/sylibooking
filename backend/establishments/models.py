from django.db import models


class Establishment(models.Model):
    """A venue that takes reservations — a hookah lounge or a restaurant.

    Lounge vs restaurant is a plain field, not a separate model: both share the
    same reservation core.
    """

    class Type(models.TextChoices):
        LOUNGE = 'lounge', 'Lounge'
        RESTAURANT = 'restaurant', 'Restaurant'

    name = models.CharField(
        max_length=200,
        help_text='Public name of the establishment, e.g. "Le Petit Baobab".',
    )
    type = models.CharField(
        max_length=20,
        choices=Type.choices,
        help_text='Lounge or restaurant. Both take reservations the same way.',
    )
    city = models.CharField(
        max_length=100,
        help_text='City the establishment operates in, e.g. "Conakry", "Labé".',
    )
    address = models.TextField(
        help_text='Street address or directions as a customer would need them.',
    )
    latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        help_text='Decimal degrees, e.g. 9.641185. Optional.',
    )
    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        help_text='Decimal degrees, e.g. -13.578401. Optional.',
    )
    opening_hours = models.TextField(
        blank=True,
        help_text=(
            'Free text for now, e.g. "Mon-Thu 18:00-02:00, Fri-Sun 16:00-04:00". '
            'Becomes structured data once availability logic needs to parse it.'
        ),
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['city', 'name']

    def __str__(self):
        return f'{self.name} ({self.city})'


class Space(models.Model):
    """A bookable unit inside an establishment: a table, VIP room or terrace."""

    class Type(models.TextChoices):
        TABLE = 'table', 'Table'
        VIP_ROOM = 'vip_room', 'VIP room'
        TERRACE = 'terrace', 'Terrace'

    establishment = models.ForeignKey(
        Establishment,
        on_delete=models.CASCADE,
        related_name='spaces',
        help_text='The establishment this space belongs to.',
    )
    name = models.CharField(
        max_length=100,
        help_text='Label the staff use, e.g. "Table 4", "VIP Room 1".',
    )
    type = models.CharField(
        max_length=20,
        choices=Type.choices,
        default=Type.TABLE,
        help_text='What kind of space this is.',
    )
    capacity = models.PositiveSmallIntegerField(
        help_text='Maximum number of guests this space seats.',
    )

    class Meta:
        ordering = ['establishment', 'name']
        constraints = [
            models.UniqueConstraint(
                fields=['establishment', 'name'],
                name='unique_space_name_per_establishment',
            ),
        ]

    def __str__(self):
        return f'{self.name} — {self.establishment.name}'