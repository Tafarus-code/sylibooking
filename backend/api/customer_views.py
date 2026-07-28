"""Customer-facing reservation endpoints, keyed by reference.

Customers have no accounts. The reference issued when a booking is created is
what proves it is theirs, so these endpoints look up by that UUID and never by
the sequential id — which anyone could guess.
"""

from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from payments.services import latest_payment_for, refresh_payment
from reservations.models import Reservation

from .serializers import PaymentSerializer, ReservationSerializer


class ReservationByReferenceView(APIView):
    """GET /api/reservations/ref/{reference}/ — a customer's own booking."""

    permission_classes = [AllowAny]

    def get_object(self, reference):
        return get_object_or_404(
            Reservation.objects.select_related('space', 'space__establishment'),
            reference=reference,
        )

    def get(self, request, reference):
        reservation = self.get_object(reference)
        return Response(ReservationSerializer(reservation).data)


class PaymentStatusView(APIView):
    """GET /api/reservations/ref/{reference}/payment/ — where the money is.

    Polls the provider rather than reporting a cached value, and applies the
    result: a payment that has completed since the last check confirms the
    booking here. This is what the customer app polls after starting a mobile
    money payment.
    """

    permission_classes = [AllowAny]

    def get(self, request, reference):
        reservation = get_object_or_404(
            Reservation.objects.select_related('space', 'space__establishment'),
            reference=reference,
        )

        payment = latest_payment_for(reservation)
        if payment is None:
            # Cash on arrival books without a payment, which is not an error.
            return Response(
                {
                    'reservation': ReservationSerializer(reservation).data,
                    'payment': None,
                    'detail': 'This booking is paid on arrival.',
                }
            )

        payment = refresh_payment(payment)
        reservation.refresh_from_db()

        return Response(
            {
                'reservation': ReservationSerializer(reservation).data,
                'payment': PaymentSerializer(payment).data,
            }
        )


class CancelReservationByReferenceView(APIView):
    """POST /api/reservations/ref/{reference}/cancel/ — customer cancels.

    Frees the slot for someone else, exactly as a merchant cancellation does.
    """

    permission_classes = [AllowAny]

    def post(self, request, reference):
        with transaction.atomic():
            reservation = get_object_or_404(
                Reservation.objects.select_for_update().select_related(
                    'space', 'space__establishment'
                ),
                reference=reference,
            )

            reason = reservation.customer_cancellable_reason()
            if reason is not None:
                return Response(
                    {'detail': reason}, status=status.HTTP_409_CONFLICT
                )

            # Cancelling an already-cancelled booking is a no-op rather than an
            # error: a customer on a flaky connection may well tap twice.
            if reservation.status != Reservation.Status.CANCELLED:
                reservation.status = Reservation.Status.CANCELLED
                reservation.save(update_fields=['status'])

        return Response(ReservationSerializer(reservation).data)
