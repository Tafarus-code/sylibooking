from django.conf import settings
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
            'Free-text note shown under the structured hours, e.g. "Kitchen '
            'closes at 23:00". Superseded by the OpeningHours rows for '
            'anything the apps compute from.'
        ),
    )
    staff = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        blank=True,
        related_name='establishments',
        help_text=(
            'Users who may see and manage this establishment\'s reservations '
            'in the merchant app.'
        ),
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['city', 'name']

    def __str__(self):
        return f'{self.name} ({self.city})'


class OpeningHours(models.Model):
    """When an establishment is open on one weekday.

    A closing time earlier than the opening time means the venue runs past
    midnight — 18:00 to 02:00 is the ordinary case for a lounge here, not an
    edge case. That interval belongs to the day it *starts* on, so Monday
    18:00-02:00 covers Tuesday morning.
    """

    class Day(models.IntegerChoices):
        # Matches datetime.weekday(), so no arithmetic is needed to line them up.
        MONDAY = 0, 'Monday'
        TUESDAY = 1, 'Tuesday'
        WEDNESDAY = 2, 'Wednesday'
        THURSDAY = 3, 'Thursday'
        FRIDAY = 4, 'Friday'
        SATURDAY = 5, 'Saturday'
        SUNDAY = 6, 'Sunday'

    establishment = models.ForeignKey(
        Establishment,
        on_delete=models.CASCADE,
        related_name='hours',
    )
    day_of_week = models.IntegerField(
        choices=Day.choices,
        help_text='0 is Monday, matching Python\'s datetime.weekday().',
    )
    is_closed = models.BooleanField(
        default=False,
        help_text='Closed all day. Opens/closes are ignored when set.',
    )
    opens = models.TimeField(
        null=True,
        blank=True,
        help_text='Ignored when closed all day.',
    )
    closes = models.TimeField(
        null=True,
        blank=True,
        help_text=(
            'Earlier than opens means the venue runs past midnight, e.g. '
            '18:00 to 02:00.'
        ),
    )

    class Meta:
        ordering = ['establishment', 'day_of_week']
        verbose_name_plural = 'opening hours'
        constraints = [
            models.UniqueConstraint(
                fields=['establishment', 'day_of_week'],
                name='unique_hours_per_day_per_establishment',
            ),
        ]

    def __str__(self):
        if self.is_closed or self.opens is None or self.closes is None:
            return f'{self.get_day_of_week_display()}: closed'
        return (
            f'{self.get_day_of_week_display()}: '
            f'{self.opens:%H:%M}-{self.closes:%H:%M}'
        )

    @property
    def runs_past_midnight(self):
        """True when this interval spills into the following day."""
        if self.is_closed or self.opens is None or self.closes is None:
            return False
        return self.closes <= self.opens

    def covers(self, moment, from_previous_day=False):
        """Whether this interval is open at ``moment`` (a time).

        ``from_previous_day`` asks about the tail of an overnight interval:
        Monday 18:00-02:00 covers Tuesday 01:00, and it is Monday's row that
        has to answer for it.
        """
        if self.is_closed or self.opens is None or self.closes is None:
            return False

        if from_previous_day:
            return self.runs_past_midnight and moment < self.closes

        if self.runs_past_midnight:
            # Open from `opens` until midnight; the rest is tomorrow's problem.
            return moment >= self.opens
        return self.opens <= moment < self.closes


class MenuItem(models.Model):
    """Something an establishment sells, shown on its detail screen.

    Browsing only — there is no ordering flow, so this carries no stock or
    preparation state. Unavailable items stay on the record rather than being
    deleted, so a seasonal item can come back without being retyped.
    """

    class Category(models.TextChoices):
        FOOD = 'food', 'Food'
        DRINK = 'drink', 'Drink'
        CHICHA_FLAVOR = 'chicha_flavor', 'Chicha flavour'

    establishment = models.ForeignKey(
        Establishment,
        on_delete=models.CASCADE,
        related_name='menu_items',
    )
    name = models.CharField(max_length=200)
    description = models.CharField(
        max_length=300,
        blank=True,
        help_text='One line at most; this is a browsing screen.',
    )
    category = models.CharField(max_length=20, choices=Category.choices)
    price = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        help_text='In Guinean francs.',
    )
    is_available = models.BooleanField(
        default=True,
        help_text='Unavailable items are hidden from customers, not deleted.',
    )

    class Meta:
        ordering = ['category', 'name']

    def __str__(self):
        return f'{self.name} ({self.get_category_display()}) — {self.price}'


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