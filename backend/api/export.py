"""Handing an accountant a file.

A venue's books leave this system exactly once a month, into somebody else's
spreadsheet. That makes CSV the right format and the only one worth building:
it opens in every tool anybody here uses, including the ones that are a phone
and a borrowed laptop.

Written with the `csv` module rather than by joining commas. A venue called
"Chez Sory, Kaloum" and a customer who typed a newline into their name are
both ordinary, and both turn a hand-rolled export into a file that silently
loses a column — which nobody notices until the totals disagree and there is
no way left to tell which row moved.

Owner and manager only. What a venue took is the sort of thing a floor
member has no business copying out wholesale, even though they can read
tonight's takings on the dashboard.
"""

import csv
from datetime import date as date_cls
from io import StringIO

from django.db.models import Q
from django.http import HttpResponse
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from establishments.permissions import (
    get_establishment_or_404,
    require_profile_access,
)
from payments.models import Payment
from reservations.models import Reservation

#: What may be exported. Named rather than free-form: an export is a promise
#: about columns, and a caller that can ask for anything gets a different
#: promise every release.
KINDS = ('bookings', 'payments')

#: Longest range answerable in one request. A year of a busy venue is a large
#: file built in memory; beyond that the honest answer is two requests.
MAX_DAYS = 366


def _parse_date(raw, field):
    if not raw:
        return None
    try:
        return date_cls.fromisoformat(raw)
    except ValueError:
        raise ValidationError(
            {field: f'"{raw}" is not a valid YYYY-MM-DD date.'}
        ) from None


class MerchantExportView(APIView):
    """GET /api/merchant/establishments/<pk>/export/?kind=&date_from=&date_to=

    Returns text/csv with a filename, so a browser saves it and the app can
    write it straight to a file rather than parsing anything.
    """

    permission_classes = [IsAuthenticated]

    default_window_days = 30

    def get(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        kind = request.query_params.get('kind', 'bookings')
        if kind not in KINDS:
            raise ValidationError(
                {'kind': f'Pick one of {", ".join(KINDS)}.'}
            )

        today = timezone.localtime().date()
        date_from = _parse_date(
            request.query_params.get('date_from'), 'date_from'
        ) or today - timezone.timedelta(days=self.default_window_days)
        date_to = (
            _parse_date(request.query_params.get('date_to'), 'date_to') or today
        )

        if date_to < date_from:
            raise ValidationError(
                {'date_to': 'The end of the range is before its start.'}
            )
        if (date_to - date_from).days > MAX_DAYS:
            raise ValidationError(
                {'date_from': f'Ranges are limited to {MAX_DAYS} days.'}
            )

        rows = (
            self._bookings(establishment, date_from, date_to)
            if kind == 'bookings'
            else self._payments(establishment, date_from, date_to)
        )

        buffer = StringIO()
        writer = csv.writer(buffer)
        writer.writerows(rows)

        response = HttpResponse(
            # BOM first, deliberately. Excel opens a UTF-8 CSV as the system
            # code page otherwise, and every accented dish name in the file
            # arrives mangled on the one machine the accountant uses.
            '﻿' + buffer.getvalue(),
            content_type='text/csv; charset=utf-8',
        )
        name = f'{establishment.id}-{kind}-{date_from}-to-{date_to}.csv'
        response['Content-Disposition'] = f'attachment; filename="{name}"'
        return response

    def _bookings(self, establishment, date_from, date_to):
        yield [
            'reference',
            'date',
            'time',
            'customer',
            'phone',
            'space',
            'party_size',
            'status',
            'payment_method',
            'payment_status',
            'amount',
        ]

        bookings = (
            Reservation.objects.filter(
                space__establishment=establishment,
                datetime__date__gte=date_from,
                datetime__date__lte=date_to,
            )
            .select_related('space')
            .prefetch_related('payments')
            .order_by('datetime')
        )

        for booking in bookings:
            when = timezone.localtime(booking.datetime)
            payment = booking.latest_payment
            yield [
                booking.reference,
                when.date().isoformat(),
                when.strftime('%H:%M'),
                booking.customer_name,
                booking.customer_phone,
                booking.space.name,
                booking.party_size,
                booking.get_status_display(),
                booking.payment_provider,
                '' if payment is None else payment.status,
                '' if payment is None else payment.amount,
            ]

    def _payments(self, establishment, date_from, date_to):
        yield [
            'created',
            'provider_reference',
            'booking_reference',
            'order_reference',
            'provider',
            'status',
            'amount',
        ]

        payments = (
            Payment.objects.filter(
                created_at__date__gte=date_from,
                created_at__date__lte=date_to,
            )
            .filter(
                # A payment reaches its venue through whichever of its two
                # parents it has — a booking or a standalone order. Neither is
                # guaranteed, so both are asked.
                Q(reservation__space__establishment=establishment)
                | Q(order__establishment=establishment)
            )
            .select_related('reservation', 'order')
            .order_by('created_at')
        )

        for payment in payments:
            yield [
                timezone.localtime(payment.created_at).isoformat(
                    timespec='seconds'
                ),
                payment.provider_reference,
                '' if payment.reservation is None else payment.reservation.reference,
                '' if payment.order is None else payment.order.reference,
                payment.provider,
                payment.status,
                payment.amount,
            ]
