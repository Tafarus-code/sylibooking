"""Serialisers for pickup orders, customer side and merchant side."""

from django.utils import timezone
from django.utils.translation import gettext as _
from orders.models import Order, OrderItem
from rest_framework import serializers

from establishments.models import MenuItem
from payments.models import Payment
from reservations.models import Reservation


class OrderItemSerializer(serializers.ModelSerializer):
    """A line as it is read back — the dish, and what it actually cost."""

    menu_item_name = serializers.CharField(source='menu_item.name')
    line_total = serializers.DecimalField(max_digits=14, decimal_places=2)

    class Meta:
        model = OrderItem
        fields = [
            'id',
            'menu_item',
            'menu_item_name',
            'quantity',
            'unit_price_at_order',
            'line_total',
        ]
        read_only_fields = fields


class OrderSerializer(serializers.ModelSerializer):
    """An order as both apps read it."""

    items = OrderItemSerializer(many=True, read_only=True)
    establishment_name = serializers.CharField(
        source='establishment.name', read_only=True
    )
    status_display = serializers.CharField(
        source='get_status_display', read_only=True
    )
    total = serializers.DecimalField(
        max_digits=14, decimal_places=2, read_only=True
    )
    payment_provider = serializers.CharField(read_only=True)
    payment_status = serializers.CharField(read_only=True)
    is_paid = serializers.BooleanField(read_only=True)
    payment_provider_display = serializers.SerializerMethodField()
    can_advance = serializers.SerializerMethodField()
    next_status = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = [
            'id',
            'reference',
            'establishment',
            'establishment_name',
            'reservation',
            'customer_name',
            'customer_phone',
            'pickup_time',
            'status',
            'status_display',
            'created_at',
            'items',
            'total',
            'payment_provider',
            'payment_provider_display',
            'payment_status',
            'is_paid',
            'can_advance',
            'next_status',
        ]
        read_only_fields = fields

    def get_payment_provider_display(self, order):
        provider = order.payment_provider
        if provider is None:
            # No row at all means cash: nothing was collected up front.
            return Payment.Provider.CASH_ON_ARRIVAL.label
        return Payment.Provider(provider).label

    def get_next_status(self, order):
        return Order.NEXT_STATUS.get(order.status)

    def get_can_advance(self, order):
        """Whether the merchant may move this order on right now.

        Mirrors the server-side check exactly, so the app can grey a button
        out for the same reason the API would refuse it.
        """
        if order.status in Order.TERMINAL_STATUSES:
            return False
        return not order.needs_payment_before_progressing


class OrderLineInputSerializer(serializers.Serializer):
    """One line of an incoming cart."""

    menu_item = serializers.IntegerField()
    quantity = serializers.IntegerField(min_value=1, max_value=99)


class OrderCreateSerializer(serializers.Serializer):
    """A cart, a pickup time, and how it is being paid for.

    Notably absent: prices and a total. What a dish costs is the menu's to
    say, not the client's — the server reads MenuItem.price and snapshots it.
    """

    establishment = serializers.IntegerField()
    customer_name = serializers.CharField(max_length=200)
    customer_phone = serializers.CharField(max_length=30)
    pickup_time = serializers.DateTimeField()
    items = OrderLineInputSerializer(many=True)
    reservation_reference = serializers.UUIDField(required=False)
    payment_provider = serializers.ChoiceField(
        choices=Payment.Provider.choices,
        default=Payment.Provider.CASH_ON_ARRIVAL,
    )

    def validate_items(self, items):
        if not items:
            raise serializers.ValidationError(_('An order needs at least one item.'))

        seen = set()
        for line in items:
            if line['menu_item'] in seen:
                raise serializers.ValidationError(
                    _('Each dish should appear once, with a quantity.')
                )
            seen.add(line['menu_item'])
        return items

    def validate_pickup_time(self, when):
        if when <= timezone.now():
            raise serializers.ValidationError(
                _('Pick a collection time in the future.')
            )
        return when

    def validate_reservation_reference(self, reference):
        reservation = Reservation.objects.filter(reference=reference).first()
        if reservation is None:
            raise serializers.ValidationError(_('No such booking.'))
        return reservation


def resolve_menu_items(establishment, lines):
    """Match the cart against the venue's own available menu.

    Refuses anything that is not on this establishment's menu or is marked
    unavailable — a stale cart from ten minutes ago must not put a sold-out
    dish into the kitchen.
    """
    wanted = {line['menu_item'] for line in lines}
    found = {
        item.pk: item
        for item in MenuItem.objects.filter(
            pk__in=wanted, establishment=establishment, is_available=True
        )
    }

    missing = wanted - set(found)
    if missing:
        raise serializers.ValidationError(
            {
                'items': (
                    _(
                        'Some of those dishes are no longer on the menu or '
                        'have sold out. Check your basket and try again.'
                    )
                )
            }
        )
    return found
