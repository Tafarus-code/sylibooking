from django.conf import settings
from django.utils import timezone
from rest_framework import serializers

from establishments.models import Establishment, Space
from reservations.availability import is_space_available
from reservations.models import Reservation


class SpaceSerializer(serializers.ModelSerializer):
    type_display = serializers.CharField(source='get_type_display', read_only=True)

    class Meta:
        model = Space
        fields = ['id', 'name', 'type', 'type_display', 'capacity']


class EstablishmentListSerializer(serializers.ModelSerializer):
    """Slim payload for the customer's browse screen."""

    type_display = serializers.CharField(source='get_type_display', read_only=True)
    space_count = serializers.IntegerField(read_only=True)

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
        ]


class EstablishmentDetailSerializer(serializers.ModelSerializer):
    type_display = serializers.CharField(source='get_type_display', read_only=True)
    spaces = SpaceSerializer(many=True, read_only=True)

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
            'opening_hours',
            'spaces',
            'created_at',
        ]


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