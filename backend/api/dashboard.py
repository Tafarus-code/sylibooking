"""The merchant's takings at a glance.

Answers three questions a venue owner actually asks at the end of a shift:
how much did I take, how much is still owed, and which bookings need chasing.
Scoped to the caller's own establishments, like every other merchant endpoint.
"""

from datetime import date as date_cls
from decimal import Decimal

from django.db.models import Count, Q, Sum
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.permissions import (
    get_establishment_or_404,
    require_operations_access,
)
from payments.models import Payment
from reservations.models import Reservation

ZERO = Decimal('0.00')


def _parse_date(raw, field):
    if not raw:
        return None
    try:
        return date_cls.fromisoformat(raw)
    except ValueError:
        raise ValidationError(
            {field: f'"{raw}" is not a valid YYYY-MM-DD date.'}
        ) from None


class PaymentDashboardView(APIView):
    """GET /api/dashboard/payments/?date_from=&date_to=

    Defaults to the last 30 days, which is the window a merchant reconciles
    against. Amounts are strings, as elsewhere, so no client rounds money.
    """

    permission_classes = [IsAuthenticated]

    default_window_days = 30

    def get(self, request):
        today = timezone.localtime().date()
        date_from = _parse_date(
            request.query_params.get('date_from'), 'date_from'
        ) or today - timezone.timedelta(days=self.default_window_days)
        date_to = (
            _parse_date(request.query_params.get('date_to'), 'date_to') or today
        )

        # One venue at a time, named explicitly: a merged figure across venues
        # is not a number any single venue's owner can act on.
        establishment_id = request.query_params.get('establishment')
        if not establishment_id:
            raise ValidationError(
                {
                    'establishment': (
                        'Required. Pick a venue; figures are no longer merged '
                        'across venues.'
                    )
                }
            )
        establishment = get_establishment_or_404(establishment_id)
        require_operations_access(request.user, establishment)
        establishments = [establishment]

        reservations = Reservation.objects.filter(
            space__establishment__in=establishments,
            datetime__date__gte=date_from,
            datetime__date__lte=date_to,
        )
        payments = Payment.objects.filter(reservation__in=reservations)

        return Response(
            {
                'period': {'from': date_from, 'to': date_to},
                'establishments': [
                    {'id': e.id, 'name': e.name} for e in establishments
                ],
                'reservations': self._reservation_counts(reservations),
                'payments': self._payment_totals(payments),
                'by_provider': self._by_provider(reservations, payments),
                'needs_attention': self._needs_attention(establishments),
            }
        )

    def _reservation_counts(self, reservations):
        counts = reservations.aggregate(
            total=Count('id'),
            **{
                status: Count('id', filter=Q(status=status))
                for status, _ in Reservation.Status.choices
            },
        )
        return counts

    def _payment_totals(self, payments):
        """Money in, money still owed, money that failed."""
        totals = payments.aggregate(
            collected=Sum('amount', filter=Q(status=Payment.Status.COMPLETED)),
            awaiting=Sum('amount', filter=Q(status=Payment.Status.PENDING)),
            failed=Sum('amount', filter=Q(status=Payment.Status.FAILED)),
            completed_count=Count('id', filter=Q(status=Payment.Status.COMPLETED)),
            pending_count=Count('id', filter=Q(status=Payment.Status.PENDING)),
            failed_count=Count('id', filter=Q(status=Payment.Status.FAILED)),
        )
        return {
            'collected': str(totals['collected'] or ZERO),
            'awaiting': str(totals['awaiting'] or ZERO),
            'failed': str(totals['failed'] or ZERO),
            'completed_count': totals['completed_count'],
            'pending_count': totals['pending_count'],
            'failed_count': totals['failed_count'],
        }

    def _by_provider(self, reservations, payments):
        """One row per provider, cash included.

        Cash has no Payment rows, so its count comes from the reservations
        that have no payment at all — otherwise the busiest column on the
        dashboard would simply be missing.
        """
        rows = []

        cash_count = reservations.filter(payments__isnull=True).count()
        rows.append(
            {
                'provider': Payment.Provider.CASH_ON_ARRIVAL,
                'provider_display': Payment.Provider.CASH_ON_ARRIVAL.label,
                'bookings': cash_count,
                'collected': str(ZERO),
                'awaiting': str(ZERO),
            }
        )

        for provider in [Payment.Provider.ORANGE_MONEY, Payment.Provider.MTN_MONEY]:
            for_provider = payments.filter(provider=provider)
            totals = for_provider.aggregate(
                collected=Sum(
                    'amount', filter=Q(status=Payment.Status.COMPLETED)
                ),
                awaiting=Sum('amount', filter=Q(status=Payment.Status.PENDING)),
            )
            rows.append(
                {
                    'provider': provider,
                    'provider_display': provider.label,
                    'bookings': for_provider.count(),
                    'collected': str(totals['collected'] or ZERO),
                    'awaiting': str(totals['awaiting'] or ZERO),
                }
            )
        return rows

    def _needs_attention(self, establishments):
        """Upcoming bookings whose mobile money has not arrived.

        Deliberately not limited to the reporting window: a booking next month
        with a failed payment is the one worth chasing today.
        """
        stuck = (
            Reservation.objects.filter(
                space__establishment__in=establishments,
                status=Reservation.Status.PENDING,
                datetime__gte=timezone.now(),
                payments__status__in=[
                    Payment.Status.PENDING,
                    Payment.Status.FAILED,
                ],
            )
            .select_related('space', 'space__establishment')
            .distinct()
            .order_by('datetime')
        )

        return [
            {
                'id': reservation.id,
                'customer_name': reservation.customer_name,
                'datetime': reservation.datetime,
                'space_name': reservation.space.name,
                'establishment_name': reservation.space.establishment.name,
                'payment_status': reservation.payment_status,
                'payment_provider_display': Payment.Provider(
                    reservation.payment_provider
                ).label,
            }
            for reservation in stuck[:20]
        ]
