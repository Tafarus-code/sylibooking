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

from reservations.models import Reservation

from .serializers import ReservationSerializer


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
