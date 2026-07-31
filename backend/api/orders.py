"""Ordering ahead: the customer places, the kitchen works the queue.

Two audiences on one model. The customer side is account-less and keyed by the
order's reference, exactly as bookings are. The merchant side is token
authenticated and scoped to venues the caller actually works at.
"""

from django.db import transaction
from django.utils import timezone
from orders.models import Order, OrderItem
from orders.rules import order_refusal_reason
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.permissions import (
    get_establishment_or_404,
    require_operations_access,
)
from payments.services import refresh_payment, start_order_payment

from .order_serializers import (
    OrderCreateSerializer,
    OrderSerializer,
    resolve_menu_items,
)


def order_queryset():
    """Everything a serialised order needs, in as few queries as possible."""
    return Order.objects.select_related(
        'establishment', 'reservation'
    ).prefetch_related('items__menu_item', 'payments')


class OrderCreateView(APIView):
    """Place an order. No account, no login — the reference is the receipt."""

    permission_classes = [AllowAny]

    def post(self, request):
        form = OrderCreateSerializer(data=request.data)
        form.is_valid(raise_exception=True)
        data = form.validated_data

        establishment = get_establishment_or_404(data['establishment'])

        refusal = order_refusal_reason(establishment)
        if refusal:
            # A validation error, not a 404: the venue exists and the customer
            # is entitled to be told why it will not take the order.
            raise ValidationError({'establishment': refusal})

        menu_items = resolve_menu_items(establishment, data['items'])

        reservation = data.get('reservation_reference')
        if reservation is not None and reservation.space.establishment_id != (
            establishment.pk
        ):
            raise ValidationError(
                {
                    'reservation_reference': (
                        'That booking is for a different venue.'
                    )
                }
            )

        with transaction.atomic():
            order = Order.objects.create(
                establishment=establishment,
                reservation=reservation,
                customer_name=data['customer_name'],
                customer_phone=data['customer_phone'],
                pickup_time=data['pickup_time'],
            )
            OrderItem.objects.bulk_create(
                [
                    OrderItem(
                        order=order,
                        menu_item=menu_items[line['menu_item']],
                        quantity=line['quantity'],
                        # Snapshotted here and never read from the menu again.
                        unit_price_at_order=menu_items[
                            line['menu_item']
                        ].price,
                    )
                    for line in data['items']
                ]
            )

        # Outside the transaction: the provider is a network call, and holding
        # a row lock open across it is how a busy kitchen ends up deadlocked.
        start_order_payment(order, data['payment_provider'])

        order = order_queryset().get(pk=order.pk)
        return Response(
            OrderSerializer(order).data, status=status.HTTP_201_CREATED
        )


class CustomerOrderView(APIView):
    """Follow your own order, by the reference you were given."""

    permission_classes = [AllowAny]

    def get(self, request, reference):
        order = order_queryset().filter(reference=reference).first()
        if order is None:
            return Response(
                {'detail': 'No such order.'}, status=status.HTTP_404_NOT_FOUND
            )

        # Poll the provider while we are here, so a customer refreshing the
        # tracking screen is what settles a payment that went through.
        payment = order.latest_payment
        if payment is not None:
            refresh_payment(payment)
            order = order_queryset().get(pk=order.pk)

        return Response(OrderSerializer(order).data)


class MerchantOrderListView(APIView):
    """The kitchen queue for one venue.

    Day-to-day operations, so every member can see it whatever their role —
    the same rule the reservation list follows.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        establishment_id = request.query_params.get('establishment')
        if not establishment_id:
            raise ValidationError(
                {'establishment': 'Say which venue this queue is for.'}
            )

        establishment = get_establishment_or_404(establishment_id)
        require_operations_access(request.user, establishment)

        orders = order_queryset().filter(establishment=establishment)

        # Default to the day being worked. A kitchen screen showing last
        # Tuesday's tickets is worse than useless.
        date = request.query_params.get('date')
        if date:
            orders = orders.filter(pickup_time__date=date)
        else:
            orders = orders.filter(
                pickup_time__date=timezone.localdate()
            )

        if request.query_params.get('status'):
            orders = orders.filter(status=request.query_params['status'])

        return Response({'results': OrderSerializer(orders, many=True).data})


class MerchantOrderStatusView(APIView):
    """Move an order along the kitchen's path."""

    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        order = order_queryset().filter(pk=pk).first()
        if order is None:
            return Response(
                {'detail': 'No such order.'}, status=status.HTTP_404_NOT_FOUND
            )

        require_operations_access(request.user, order.establishment)

        target = request.data.get('status')
        if target not in Order.Status.values:
            raise ValidationError({'status': 'Not a status an order can have.'})

        if order.status in Order.TERMINAL_STATUSES:
            return Response(
                {
                    'detail': (
                        f'This order is already '
                        f'{order.get_status_display().lower()}.'
                    )
                },
                status=status.HTTP_409_CONFLICT,
            )

        # Cancelling is always allowed; everything else follows the path.
        if target != Order.Status.CANCELLED:
            expected = Order.NEXT_STATUS.get(order.status)
            if target != expected:
                return Response(
                    {
                        'detail': (
                            f'An order goes {order.get_status_display().lower()}'
                            f' → {Order.Status(expected).label.lower()}, not '
                            f'straight to {Order.Status(target).label.lower()}.'
                        )
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            # The same gate the reservation confirm uses, for the same reason:
            # cash on pickup is worked on trust, mobile money is not. Enforced
            # here rather than by hiding a button, since the API is reachable
            # directly.
            if order.needs_payment_before_progressing:
                payment = order.latest_payment
                refresh_payment(payment)
                order.refresh_from_db()
                if order.needs_payment_before_progressing:
                    return Response(
                        {
                            'detail': (
                                f'{payment.get_provider_display()} payment is '
                                f'{payment.get_status_display().lower()}. '
                                f'Start this order once the payment '
                                f'completes, or cancel it.'
                            )
                        },
                        status=status.HTTP_409_CONFLICT,
                    )

        order.status = target
        order.save(update_fields=['status'])

        order = order_queryset().get(pk=order.pk)
        return Response(OrderSerializer(order).data)
