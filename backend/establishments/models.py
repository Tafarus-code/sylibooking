import uuid

from django.conf import settings
from django.core.validators import (
    FileExtensionValidator,
    MaxValueValidator,
    MinValueValidator,
)
from django.db import models
from django.utils.translation import gettext_lazy as _

from .theme_presets import DEFAULT_PRESET, PRESET_CHOICES


def _scattered_upload_path(folder, establishment_id, filename):
    """A stable folder per venue, with an unguessable filename.

    The original name is discarded: it can carry a person's name or a path
    from their phone, and two uploads called IMG_0001.jpg must not collide.
    """
    extension = filename.rsplit('.', 1)[-1].lower() if '.' in filename else 'jpg'
    return f'{folder}/{establishment_id}/{uuid.uuid4().hex}.{extension}'


def menu_item_upload_path(instance, filename):
    return _scattered_upload_path('menu', instance.establishment_id, filename)


class Establishment(models.Model):
    """A venue that takes reservations — a hookah lounge or a restaurant.

    Lounge vs restaurant is a plain field, not a separate model: both share the
    same reservation core.
    """

    class Type(models.TextChoices):
        LOUNGE = 'lounge', _('Lounge')
        RESTAURANT = 'restaurant', _('Restaurant')

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
    description = models.TextField(
        blank=True,
        help_text='Longer blurb shown on the customer detail screen.',
    )
    tagline = models.CharField(
        max_length=200,
        blank=True,
        help_text='One line, e.g. "Rooftop chicha over Kaloum".',
    )
    theme_preset = models.CharField(
        max_length=30,
        choices=PRESET_CHOICES,
        default=DEFAULT_PRESET,
        help_text=(
            'Which curated branding preset this venue uses. The key is the '
            'only thing stored — colours and fonts live in the shared design '
            'file, so a merchant cannot pick something unreadable.'
        ),
    )
    staff = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        blank=True,
        through='MerchantMembership',
        related_name='establishments',
        help_text=(
            'Users who may see and manage this establishment in the merchant '
            'app. What each may actually do is decided by their membership '
            'role, not by this field.'
        ),
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['city', 'name']

    def __str__(self):
        return f'{self.name} ({self.city})'

    def visible_reviews(self):
        """Reviews a customer may see. Hidden ones count for nothing."""
        return [review for review in self.reviews.all() if not review.is_hidden]

    @property
    def review_count(self):
        return len(self.visible_reviews())

    @property
    def average_rating(self):
        """Mean of visible ratings, to one decimal, or None with no reviews.

        Computed rather than stored: a denormalised average drifts the moment
        a review is hidden, and hiding is the whole point of moderation.
        """
        ratings = [review.rating for review in self.visible_reviews()]
        if not ratings:
            return None
        return round(sum(ratings) / len(ratings), 1)


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
        FOOD = 'food', _('Food')
        DRINK = 'drink', _('Drink')
        CHICHA_FLAVOR = 'chicha_flavor', _('Chicha flavour')

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
    image = models.ImageField(
        upload_to=menu_item_upload_path,
        blank=True,
        null=True,
        validators=[
            FileExtensionValidator(
                allowed_extensions=settings.ALLOWED_PHOTO_EXTENSIONS
            )
        ],
        help_text='Optional. Most items will not have one, especially at first.',
    )
    is_available = models.BooleanField(
        default=True,
        help_text='Unavailable items are hidden from customers, not deleted.',
    )

    class Meta:
        ordering = ['category', 'name']

    def __str__(self):
        return f'{self.name} ({self.get_category_display()}) — {self.price}'


class MerchantMembership(models.Model):
    """A user's standing at one establishment.

    The through model for ``Establishment.staff``. Access and authority are
    the same relationship — being listed is what grants access, and the role
    is what decides how far it goes — so one row carries both rather than
    keeping a separate permissions table in step with a membership table.
    """

    class Role(models.TextChoices):
        OWNER = 'owner', _('Owner')
        MANAGER = 'manager', _('Manager')
        STAFF = 'staff', _('Staff')

    #: May edit the venue's public profile: hours, menu, photos, description.
    PROFILE_ROLES = frozenset({Role.OWNER, Role.MANAGER})
    #: May add, remove and re-role other members. Deliberately owner alone.
    MEMBERSHIP_ROLES = frozenset({Role.OWNER})
    #: May run the floor: reservations, confirmations, payment status.
    OPERATIONS_ROLES = frozenset({Role.OWNER, Role.MANAGER, Role.STAFF})

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='merchant_memberships',
    )
    establishment = models.ForeignKey(
        Establishment,
        on_delete=models.CASCADE,
        related_name='memberships',
    )
    role = models.CharField(
        max_length=20,
        choices=Role.choices,
        default=Role.STAFF,
        help_text=(
            'Owner: everything, including managing who else has access. '
            'Manager: the venue and its profile, but not the staff list. '
            'Staff: day-to-day floor work, plus toggling menu availability.'
        ),
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['establishment', 'role', 'user']
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'establishment'],
                name='unique_membership_per_user_per_establishment',
            ),
        ]

    def __str__(self):
        return (
            f'{self.user} — {self.get_role_display()} at '
            f'{self.establishment.name}'
        )

    @property
    def can_edit_profile(self):
        return self.role in self.PROFILE_ROLES

    @property
    def can_manage_staff(self):
        return self.role in self.MEMBERSHIP_ROLES

    @property
    def can_toggle_menu_availability(self):
        """The one operational exception.

        Staff cannot edit a menu item, but they can mark it sold out — that
        is a floor decision made mid-service, and routing it through a
        manager would mean customers ordering things the kitchen has run out
        of.
        """
        return self.role in self.OPERATIONS_ROLES


def photo_upload_path(instance, filename):
    return _scattered_upload_path(
        'establishments', instance.establishment_id, filename
    )


class Review(models.Model):
    """One customer's verdict on one visit.

    Tied to a reservation rather than floating free, so a review can only come
    from someone who actually booked — and the OneToOne means one review per
    visit, not per customer, so a regular can review each time they come.
    """

    establishment = models.ForeignKey(
        Establishment,
        on_delete=models.CASCADE,
        related_name='reviews',
    )
    reservation = models.OneToOneField(
        'reservations.Reservation',
        on_delete=models.CASCADE,
        related_name='review',
        help_text='The visit being reviewed. One review per booking.',
    )
    rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)],
        help_text='1 to 5.',
    )
    comment = models.TextField(
        blank=True,
        help_text='Optional — a rating on its own is a valid review.',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    is_hidden = models.BooleanField(
        default=False,
        help_text=(
            'Hidden reviews are excluded from every customer-facing response '
            'and from the average rating. Moderation only; never exposed.'
        ),
    )

    class Meta:
        # -id breaks ties: two reviews written in the same millisecond would
        # otherwise come back in an arbitrary order, which paginates badly.
        ordering = ['-created_at', '-id']
        constraints = [
            models.CheckConstraint(
                condition=models.Q(rating__gte=1) & models.Q(rating__lte=5),
                name='review_rating_between_1_and_5',
            ),
        ]

    def __str__(self):
        return f'{self.rating}/5 for {self.establishment.name}'

    @property
    def author_display_name(self):
        """First name only.

        The booking carries a full name and a phone number; a public review
        needs neither. This is the least that still reads as a person.
        """
        full = (self.reservation.customer_name or '').strip()
        return full.split()[0] if full else 'Guest'


class Photo(models.Model):
    """A picture of an establishment, from the venue or from a customer."""

    class UploaderRole(models.TextChoices):
        CUSTOMER = 'customer', 'Customer'
        MERCHANT = 'merchant', 'Merchant'

    establishment = models.ForeignKey(
        Establishment,
        on_delete=models.CASCADE,
        related_name='photos',
    )
    uploaded_by_role = models.CharField(
        max_length=20,
        choices=UploaderRole.choices,
        help_text='Merchant photos are the venue\'s own; customer photos are not.',
    )
    reservation = models.ForeignKey(
        'reservations.Reservation',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='photos',
        help_text=(
            'The booking a customer uploaded this from. Null for the venue\'s '
            'own photos.'
        ),
    )
    image = models.ImageField(
        upload_to=photo_upload_path,
        validators=[
            FileExtensionValidator(
                allowed_extensions=settings.ALLOWED_PHOTO_EXTENSIONS
            )
        ],
    )
    caption = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    is_hidden = models.BooleanField(
        default=False,
        help_text=(
            'Hidden photos are excluded from every customer-facing response. '
            'Moderation only.'
        ),
    )

    class Meta:
        ordering = ['-created_at', '-id']

    def __str__(self):
        return (
            f'{self.get_uploaded_by_role_display()} photo of '
            f'{self.establishment.name}'
        )


class Space(models.Model):
    """A bookable unit inside an establishment: a table, VIP room or terrace."""

    class Type(models.TextChoices):
        TABLE = 'table', _('Table')
        VIP_ROOM = 'vip_room', _('VIP room')
        TERRACE = 'terrace', _('Terrace')

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

# Imported last so the model is registered with the app, while its own
# module stays free of the rest of establishments' imports.
from .favourites import Favourite  # noqa: E402, F401
