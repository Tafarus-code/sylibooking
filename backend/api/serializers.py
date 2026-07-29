from django.conf import settings
from django.utils import timezone
from rest_framework import serializers

from establishments.hours import (
    closing_time_at,
    is_open_at,
    todays_hours,
    week_schedule,
)
from establishments.models import Establishment, MenuItem, OpeningHours, Space
from payments.models import Payment
from reservations.availability import is_space_available
from reservations.models import Reservation


class PaymentSerializer(serializers.ModelSerializer):
    """Read-only view of a payment. Nothing here is client-settable."""

    provider_display = serializers.CharField(
        source='get_provider_display', read_only=True
    )
    status_display = serializers.CharField(
        source='get_status_display', read_only=True
    )

    class Meta:
        model = Payment
        fields = [
            'id',
            'provider',
            'provider_display',
            'amount',
            'status',
            'status_display',
            'provider_reference',
            'created_at',
        ]
        read_only_fields = fields


class OpeningHoursSerializer(serializers.ModelSerializer):
    day_display = serializers.CharField(
        source='get_day_of_week_display', read_only=True
    )
    runs_past_midnight = serializers.BooleanField(read_only=True)

    class Meta:
        model = OpeningHours
        fields = [
            'day_of_week',
            'day_display',
            'is_closed',
            'opens',
            'closes',
            'runs_past_midnight',
        ]
        read_only_fields = fields


class MenuItemSerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()

    class Meta:
        model = MenuItem
        fields = ['id', 'name', 'description', 'price', 'image']
        read_only_fields = fields

    def get_image(self, item):
        """Absolute, or null — most items will have none, especially early."""
        if not item.image:
            return None
        request = self.context.get('request')
        return (
            request.build_absolute_uri(item.image.url)
            if request
            else item.image.url
        )


class MenuCategorySerializer(serializers.Serializer):
    """One category with its items. Empty categories are never emitted."""

    category = serializers.CharField(read_only=True)
    category_display = serializers.CharField(read_only=True)
    items = MenuItemSerializer(many=True, read_only=True)


class SpaceSerializer(serializers.ModelSerializer):
    type_display = serializers.CharField(source='get_type_display', read_only=True)

    class Meta:
        model = Space
        fields = ['id', 'name', 'type', 'type_display', 'capacity']


class EstablishmentListSerializer(serializers.ModelSerializer):
    """Slim payload for the customer's browse screen."""

    type_display = serializers.CharField(source='get_type_display', read_only=True)
    space_count = serializers.IntegerField(read_only=True)

    # Computed here rather than in the app: the overnight arithmetic should
    # exist once, and both apps should agree on the answer.
    is_open_now = serializers.SerializerMethodField()
    closes_at = serializers.SerializerMethodField()

    class Meta:
        model = Establishment
        fields = [
            'id',
            'name',
            'type',
            'type_display',
            'city',
            'address',
            'latitude',
            'longitude',
            'space_count',
            'is_open_now',
            'closes_at',
        ]

    def get_is_open_now(self, establishment):
        return is_open_at(establishment)

    def get_closes_at(self, establishment):
        return closing_time_at(establishment)


class EstablishmentDetailSerializer(serializers.ModelSerializer):
    type_display = serializers.CharField(source='get_type_display', read_only=True)
    spaces = SpaceSerializer(many=True, read_only=True)

    is_open_now = serializers.SerializerMethodField()
    closes_at = serializers.SerializerMethodField()
    today = serializers.SerializerMethodField()
    hours = serializers.SerializerMethodField()
    menu = serializers.SerializerMethodField()

    # Computed, never stored: a denormalised average drifts the moment a
    # review is hidden, and hiding is the point of moderation.
    average_rating = serializers.FloatField(read_only=True, allow_null=True)
    review_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Establishment
        fields = [
            'id',
            'name',
            'type',
            'type_display',
            'city',
            'address',
            'latitude',
            'longitude',
            'is_open_now',
            'closes_at',
            'today',
            'hours',
            'menu',
            'average_rating',
            'review_count',
            'opening_hours',
            'spaces',
            'created_at',
        ]

    def get_is_open_now(self, establishment):
        return is_open_at(establishment)

    def get_closes_at(self, establishment):
        """When the interval in progress ends, or null when closed."""
        return closing_time_at(establishment)

    def get_today(self, establishment):
        """The current day's hours, or null if the merchant never set them.

        Only ever the current day — falling back to another day would tell a
        customer a shut venue is open.
        """
        row = todays_hours(establishment)
        return None if row is None else OpeningHoursSerializer(row).data

    def get_hours(self, establishment):
        """All seven days, so the app can render a full week."""
        return OpeningHoursSerializer(week_schedule(establishment), many=True).data

    def get_menu(self, establishment):
        """Available items grouped by category.

        Unavailable items are excluded, and a category with nothing left in it
        is dropped entirely rather than sent as an empty group — otherwise the
        app renders a heading with nothing under it.
        """
        available = [
            item for item in establishment.menu_items.all() if item.is_available
        ]
        groups = []
        for value, label in MenuItem.Category.choices:
            items = [item for item in available if item.category == value]
            if not items:
                continue
            groups.append(
                {
                    'category': value,
                    'category_display': label,
                    'items': MenuItemSerializer(
                        items, many=True, context=self.context
                    ).data,
                }
            )
        return groups


class SlotSerializer(serializers.Serializer):
    start = serializers.DateTimeField(read_only=True)
    available = serializers.BooleanField(read_only=True)


class SpaceAvailabilitySerializer(serializers.Serializer):
    space = SpaceSerializer(read_only=True)
    slots = SlotSerializer(many=True, read_only=True)


class ReservationSerializer(serializers.ModelSerializer):
    """Read + create. Status is never client-supplied.

    A new reservation always starts pending; moving it on is the merchant's
    job, through the confirm/cancel actions.
    """

    space = serializers.PrimaryKeyRelatedField(queryset=Space.objects.all())
    space_name = serializers.CharField(source='space.name', read_only=True)
    establishment = serializers.PrimaryKeyRelatedField(
        source='space.establishment', read_only=True
    )
    establishment_name = serializers.CharField(
        source='space.establishment.name', read_only=True
    )
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    can_cancel = serializers.SerializerMethodField()

    # Written on create to choose how to pay; read back as how the booking is
    # actually being paid, cash included. The Reservation property behind it
    # reports cash_on_arrival when no Payment row exists.
    payment_provider = serializers.ChoiceField(
        choices=Payment.Provider.choices,
        required=False,
        default=Payment.Provider.CASH_ON_ARRIVAL,
        help_text=(
            'cash_on_arrival (the default) books exactly as before. A mobile '
            'money provider opens a payment, and the booking is confirmed only '
            'once that payment completes.'
        ),
    )
    payment_provider_display = serializers.SerializerMethodField()

    # Flat fields so a merchant list can render a badge per row without
    # digging into the nested payment object.
    payment_status = serializers.CharField(read_only=True, allow_null=True)
    is_paid = serializers.BooleanField(read_only=True)
    can_confirm = serializers.SerializerMethodField()

    payment = serializers.SerializerMethodField()

    def get_payment_provider_display(self, reservation):
        return Payment.Provider(reservation.payment_provider).label

    def get_can_confirm(self, reservation):
        """Whether the merchant may confirm this booking right now.

        Sent so the app can disable the button, but the server enforces it
        regardless — see ReservationViewSet.confirm.
        """
        return (
            reservation.status == Reservation.Status.PENDING
            and not reservation.needs_payment_before_confirming
        )

    def get_payment(self, reservation):
        """The most recent payment, or null for cash on arrival."""
        payment = reservation.latest_payment
        return None if payment is None else PaymentSerializer(payment).data

    def get_can_cancel(self, reservation):
        """Whether the customer may still cancel this themselves.

        Sent so the app can hide the button rather than offer an action the
        server will refuse.
        """
        return (
            reservation.status.lower() != Reservation.Status.CANCELLED
            and reservation.customer_cancellable_reason() is None
        )

    class Meta:
        model = Reservation
        fields = [
            'id',
            'reference',
            'space',
            'space_name',
            'establishment',
            'establishment_name',
            'customer_name',
            'customer_phone',
            'datetime',
            'party_size',
            'status',
            'status_display',
            'can_cancel',
            'can_confirm',
            'payment_provider',
            'payment_provider_display',
            'payment_status',
            'is_paid',
            'payment',
            'created_at',
        ]
        read_only_fields = ['status', 'reference', 'created_at']

    def validate_party_size(self, value):
        if value < 1:
            raise serializers.ValidationError('A reservation needs at least one guest.')
        return value

    def validate_datetime(self, value):
        if value < timezone.now():
            raise serializers.ValidationError('Cannot book a time in the past.')
        return value

    def validate(self, attrs):
        """Reject over-capacity and double bookings.

        The same availability check runs again inside the view under a row
        lock; this one exists to return a clean 400 rather than a race-losing
        error.
        """
        space = attrs.get('space')
        party_size = attrs.get('party_size')
        start = attrs.get('datetime')

        if space and party_size and party_size > space.capacity:
            raise serializers.ValidationError(
                {
                    'party_size': (
                        f'{space.name} seats {space.capacity}; '
                        f'{party_size} guests will not fit.'
                    )
                }
            )

        if space and start and not is_space_available(space, start):
            raise serializers.ValidationError(
                {
                    'datetime': (
                        f'{space.name} is already booked around that time. '
                        f'Bookings are held for '
                        f'{settings.RESERVATION_DURATION_MINUTES} minutes.'
                    )
                }
            )

        return attrs