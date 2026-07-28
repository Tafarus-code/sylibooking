from datetime import date as date_cls

from django.db import transaction
from django.db.models import Count
from django.shortcuts import get_object_or_404
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from establishments.models import Establishment, Space
from payments.models import Payment
from payments.services import start_payment
from reservations.availability import availability_for_establishment, is_space_available
from reservations.models import Reservation

from .serializers import (
    EstablishmentDetailSerializer,
    EstablishmentListSerializer,
    ReservationSerializer,
    SpaceAvailabilitySerializer,
)


class EstablishmentViewSet(viewsets.ReadOnlyModelViewSet):
    """Browse establishments and check what is free on a given day.

    Read-only and public: this is the customer's discovery surface. Merchants
    create and edit establishments through /admin/ for now.
    """

    permission_classes = [AllowAny]

    def get_queryset(self):
        queryset = Establishment.objects.all()

        city = self.request.query_params.get('city')
        if city:
            queryset = queryset.filter(city__iexact=city)

        type_ = self.request.query_params.get('type')
        if type_:
            queryset = queryset.filter(type=type_)

        search = self.request.query_params.get('search')
        if search:
            queryset = queryset.filter(name__icontains=search)

        if self.action == 'list':
            # annotate() adds a GROUP BY, which makes Django treat the queryset
            # as unordered and pagination inconsistent, so re-state Meta.ordering.
            return queryset.annotate(space_count=Count('spaces')).order_by(
                'city', 'name'
            )
        return queryset.prefetch_related('spaces')

    def get_serializer_class(self):
        if self.action == 'list':
            return EstablishmentListSerializer
        return EstablishmentDetailSerializer

    @action(detail=True, methods=['get'], permission_classes=[AllowAny])
    def availability(self, request, pk=None):
        """GET /api/establishments/{id}/availability/?date=&party_size=

        Returns every space with a slot grid for that day. Spaces smaller than
        ``party_size`` are omitted.
        """
        establishment = self.get_object()

        raw_date = request.query_params.get('date')
        if not raw_date:
            raise ValidationError({'date': 'Required, in YYYY-MM-DD format.'})
        try:
            day = date_cls.fromisoformat(raw_date)
        except ValueError:
            raise ValidationError(
                {'date': f'"{raw_date}" is not a valid YYYY-MM-DD date.'}
            ) from None

        raw_party_size = request.query_params.get('party_size')
        party_size = None
        if raw_party_size:
            try:
                party_size = int(raw_party_size)
            except ValueError:
                raise ValidationError(
                    {'party_size': f'"{raw_party_size}" is not a whole number.'}
                ) from None
            if party_size < 1:
                raise ValidationError(
                    {'party_size': 'A reservation needs at least one guest.'}
                )

        results = availability_for_establishment(establishment, day, party_size)
        return Response(
            {
                'establishment': establishment.id,
                'date': day,
                'party_size': party_size,
                'spaces': SpaceAvailabilitySerializer(results, many=True).data,
            }
        )


class ReservationViewSet(
    mixins.CreateModelMixin,
    mixins.RetrieveModelMixin,
    mixins.ListModelMixin,
    viewsets.GenericViewSet,
):
    """Create a booking (public) and manage bookings (merchant).

    Creating is open so a customer can book without an account — the MVP is
    pay-on-arrival with a name and phone number. Listing is not: it would
    otherwise expose every customer's name and phone to anyone.
    """

    serializer_class = ReservationSerializer

    def get_permissions(self):
        # Creating is public; everything keyed by sequential id is not.
        # Customers reach their own booking through ReservationByReferenceView,
        # which needs the unguessable reference.
        if self.action == 'create':
            return [AllowAny()]
        return [IsAuthenticated()]

    def get_queryset(self):
        queryset = (
            Reservation.objects.select_related('space', 'space__establishment')
            # The list renders a payment badge per row; without this that is a
            # query per booking across a whole day's bookings.
            .prefetch_related('payments')
            .all()
        )

        # Scope to the caller's own venues. Without this, any logged-in user
        # would see every establishment's customer names and phone numbers.
        user = self.request.user
        if not user.is_superuser:
            queryset = queryset.filter(space__establishment__staff=user)

        establishment = self.request.query_params.get('establishment')
        if establishment:
            queryset = queryset.filter(space__establishment_id=establishment)

        status_ = self.request.query_params.get('status')
        if status_:
            queryset = queryset.filter(status=status_)

        for param, lookup in [
            ('date', 'datetime__date'),
            ('date_from', 'datetime__date__gte'),
            ('date_to', 'datetime__date__lte'),
        ]:
            raw = self.request.query_params.get(param)
            if not raw:
                continue
            try:
                queryset = queryset.filter(**{lookup: date_cls.fromisoformat(raw)})
            except ValueError:
                raise ValidationError(
                    {param: f'"{raw}" is not a valid YYYY-MM-DD date.'}
                ) from None

        return queryset

    def perform_create(self, serializer):
        """Re-check availability under a row lock, then open any payment.

        The serializer already checked availability, but two requests can pass
        that check concurrently and both write. Locking the space row
        serialises them so the second one loses cleanly.
        """
        space = serializer.validated_data['space']
        start = serializer.validated_data['datetime']
        provider = serializer.validated_data.pop(
            'payment_provider', Payment.Provider.CASH_ON_ARRIVAL
        )

        with transaction.atomic():
            locked_space = get_object_or_404(
                Space.objects.select_for_update(), pk=space.pk
            )
            if not is_space_available(locked_space, start):
                raise ValidationError(
                    {'datetime': f'{locked_space.name} was just booked for that time.'}
                )
            reservation = serializer.save(status=Reservation.Status.PENDING)

            # Cash on arrival returns None and changes nothing. Mobile money
            # opens a payment and, if it completes, confirms the booking.
            start_payment(reservation, provider)

        # start_payment may have moved the reservation to confirmed; without
        # this the response would still claim it is pending.
        reservation.refresh_from_db()

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated])
    def confirm(self, request, pk=None):
        """Merchant accepts a pending booking.

        Cash on arrival may be confirmed before any money changes hands — that
        is what cash on arrival means. A mobile money booking may not: holding
        a table against a payment that is still pending, or has failed, is
        exactly the no-show the deposit exists to prevent. Enforced here rather
        than by hiding the button, since the API is reachable directly.
        """
        reservation = self.get_object()
        if reservation.status == Reservation.Status.CANCELLED:
            return Response(
                {'detail': 'A cancelled reservation cannot be confirmed.'},
                status=status.HTTP_409_CONFLICT,
            )

        if reservation.needs_payment_before_confirming:
            payment = reservation.latest_payment
            return Response(
                {
                    'detail': (
                        f'{payment.get_provider_display()} payment is '
                        f'{payment.get_status_display().lower()}. Confirm this '
                        f'booking once the payment completes, or cancel it.'
                    ),
                    'payment_status': payment.status,
                    'payment_provider': payment.provider,
                },
                status=status.HTTP_409_CONFLICT,
            )

        reservation.status = Reservation.Status.CONFIRMED
        reservation.save(update_fields=['status'])
        return Response(self.get_serializer(reservation).data)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated])
    def cancel(self, request, pk=None):
        """Merchant turns a booking down, freeing the slot."""
        reservation = self.get_object()
        if reservation.status == Reservation.Status.COMPLETED:
            return Response(
                {'detail': 'A completed reservation cannot be cancelled.'},
                status=status.HTTP_409_CONFLICT,
            )

        reservation.status = Reservation.Status.CANCELLED
        reservation.save(update_fields=['status'])
        return Response(self.get_serializer(reservation).data)