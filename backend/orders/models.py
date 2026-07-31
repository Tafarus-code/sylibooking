import uuid

from django.db import models

from establishments.models import Establishment, MenuItem


class Order(models.Model):
    """Food ordered ahead, collected at the counter.

    Pickup only. There is no delivery, no courier and no address, so an order
    is a promise to be somewhere at a time rather than a journey to plan.

    An order may hang off a table booking (`reservation`) or stand alone: a
    customer with a table pre-orders so the food lands when they do, and a
    customer without one collects and leaves.
    """

    class Status(models.TextChoices):
        PLACED = 'placed', 'Placed'
        PREPARING = 'preparing', 'Preparing'
        READY = 'ready', 'Ready'
        COMPLETED = 'completed', 'Completed'
        CANCELLED = 'cancelled', 'Cancelled'

    #: The kitchen's forward path. Anything else is a jump the API refuses.
    NEXT_STATUS = {
        Status.PLACED: Status.PREPARING,
        Status.PREPARING: Status.READY,
        Status.READY: Status.COMPLETED,
    }

    #: Statuses a merchant can no longer move on from.
    TERMINAL_STATUSES = frozenset({Status.COMPLETED, Status.CANCELLED})

    reference = models.UUIDField(
        default=uuid.uuid4,
        unique=True,
        editable=False,
        db_index=True,
        help_text=(
            'Unguessable handle the customer uses to follow their own order. '
            'Customers have no accounts, so this is what proves the order is '
            'theirs — the sequential id must not be used for that.'
        ),
    )
    establishment = models.ForeignKey(
        Establishment,
        on_delete=models.PROTECT,
        related_name='orders',
        help_text='Where the food is cooked and collected.',
    )
    reservation = models.ForeignKey(
        'reservations.Reservation',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='orders',
        help_text=(
            'The table booking this order belongs to, when there is one. Null '
            'for a standalone pickup. SET_NULL rather than CASCADE: a '
            'cancelled booking must not silently delete food the kitchen may '
            'already have started.'
        ),
    )
    customer_name = models.CharField(max_length=200)
    customer_phone = models.CharField(
        max_length=30,
        help_text='How the counter reaches the customer when it is ready.',
    )
    pickup_time = models.DateTimeField(
        help_text='When the customer says they will collect. Stored in UTC.',
    )
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PLACED,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['pickup_time', 'id']
        indexes = [
            models.Index(fields=['establishment', 'pickup_time']),
            models.Index(fields=['status']),
        ]

    def __str__(self):
        return (
            f'{self.customer_name} — {self.establishment.name} '
            f'@ {self.pickup_time:%Y-%m-%d %H:%M} '
            f'({self.get_status_display()})'
        )

    @property
    def total(self):
        """What the customer owes, from the prices snapshotted at ordering.

        Summed in Python rather than by the database because the items are
        nearly always already loaded, and a handful of lines does not warrant
        a second query.
        """
        return sum((item.line_total for item in self.items.all()), start=0)

    @property
    def latest_payment(self):
        return self.payments.order_by('-created_at').first()

    @property
    def payment_provider(self):
        payment = self.latest_payment
        return None if payment is None else payment.provider

    @property
    def payment_status(self):
        payment = self.latest_payment
        return None if payment is None else payment.status

    @property
    def is_paid(self):
        from payments.models import Payment

        payment = self.latest_payment
        return (
            payment is not None and payment.status == Payment.Status.COMPLETED
        )

    @property
    def needs_payment_before_progressing(self):
        """True when money must arrive before the kitchen may move this on.

        Cash on pickup is worked on trust, exactly as cash on arrival is for a
        table: the customer pays at the counter when they collect. A mobile
        money order that has not been paid is different — cooking it would be
        giving away food against money that never came.
        """
        from payments.models import Payment

        payment = self.latest_payment
        if payment is None:
            return False
        return (
            payment.is_mobile_money
            and payment.status != Payment.Status.COMPLETED
        )


class OrderItem(models.Model):
    """One line of an order, at the price it cost when it was placed."""

    order = models.ForeignKey(
        Order,
        on_delete=models.CASCADE,
        related_name='items',
    )
    menu_item = models.ForeignKey(
        MenuItem,
        on_delete=models.PROTECT,
        related_name='order_items',
        help_text=(
            'PROTECT rather than CASCADE: deleting a dish from the menu must '
            'not erase the record of what somebody bought.'
        ),
    )
    quantity = models.PositiveIntegerField(default=1)
    unit_price_at_order = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        help_text=(
            'Copied from MenuItem.price when the order is created, and never '
            'recalculated. A merchant raising a price this afternoon must not '
            'change what this morning owes.'
        ),
    )

    class Meta:
        ordering = ['id']

    def __str__(self):
        return f'{self.quantity} x {self.menu_item.name}'

    @property
    def line_total(self):
        return self.unit_price_at_order * self.quantity
