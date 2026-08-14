"""What a venue can learn about itself.

The payments dashboard answers "how much did I take". This answers the
questions that come after it: which nights are worth opening for, how often a
table is held for somebody who never comes, what people actually order, and
how many of them come back.

Every number here is already in the database. Nothing new is recorded to
produce them — which is why this could be built at all without a pilot, and
why it costs a merchant nothing to start reading.

Three rules the figures follow.

**One venue at a time.** Merged across venues, none of these is actionable by
the person who could act on it. Same rule as the payments dashboard.

**A number that cannot be computed is null, never zero.** A venue with no
completed sittings has no no-show rate; reporting 0% would say something
false and reassuring. The client is expected to say why it is empty rather
than draw an empty chart.

**Counts describe what happened, not what was promised.** A booking still
ahead of its time is not a cover, and a cancelled one never was.
"""

from datetime import timedelta

from django.db.models import Count, DecimalField, F, Min, Q, Sum
from django.db.models.functions import ExtractHour, TruncDate
from django.utils import timezone
from orders.models import Order, OrderItem
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.permissions import (
    get_establishment_or_404,
    require_operations_access,
)
from reservations.models import Reservation

#: The windows offered. Not free-form: a merchant comparing "last 30 days"
#: against a colleague's "last 28" is comparing nothing, and an arbitrary
#: range is a report-builder rather than a screen somebody reads on a phone.
WINDOWS = (7, 30, 90)

DEFAULT_WINDOW = 30

#: How many dishes a ranking shows. Long enough to be a list, short enough to
#: be read standing up.
TOP_DISHES = 8

#: Bookings that put people in the room. A cancelled booking never did, and a
#: missed one is counted separately as the thing that went wrong.
SERVED = (Reservation.Status.CONFIRMED, Reservation.Status.COMPLETED)


def _rate(part, whole):
    """A share, or None when there is nothing to take a share of.

    None rather than 0.0, deliberately. A venue with no finished sittings has
    no no-show rate, and a screen that prints 0% has told the merchant
    something reassuring and false.
    """
    return None if not whole else round(part / whole, 4)


class MerchantInsightsView(APIView):
    """GET /api/merchant/establishments/<pk>/insights/?days=30

    Read access, not profile access: knowing which night is busy is floor
    knowledge, and staff who work the floor already know most of it. The
    payments dashboard draws the same line.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_operations_access(request.user, establishment)

        days = self._window(request)
        now = timezone.localtime()
        start = (now - timedelta(days=days)).replace(
            hour=0, minute=0, second=0, microsecond=0
        )

        bookings = Reservation.objects.filter(
            space__establishment=establishment,
            datetime__gte=start,
            datetime__lte=now,
        )

        return Response(
            {
                'window': {
                    'days': days,
                    'from': start.date(),
                    'to': now.date(),
                    'options': list(WINDOWS),
                },
                'establishment': {
                    'id': establishment.id,
                    'name': establishment.name,
                },
                'covers': self._covers(bookings),
                'attendance': self._attendance(bookings),
                'peak_hours': self._peak_hours(bookings),
                'dishes': self._dishes(establishment, start, now),
                'repeat_customers': self._repeat_customers(
                    establishment, bookings
                ),
            }
        )

    def _window(self, request):
        raw = request.query_params.get('days')
        if raw is None:
            return DEFAULT_WINDOW
        try:
            days = int(raw)
        except ValueError:
            raise ValidationError(
                {'days': f'"{raw}" is not a number of days.'}
            ) from None
        if days not in WINDOWS:
            raise ValidationError(
                {'days': f'Pick one of {", ".join(str(w) for w in WINDOWS)}.'}
            )
        return days

    # --- Covers -----------------------------------------------------------

    def _covers(self, bookings):
        """People through the door, by date and by day of the week.

        Party size summed rather than bookings counted: two tables of two and
        one of four are the same night's work, and a venue plans staff against
        people rather than against rows.

        By weekday as well as by date because they answer different questions
        — "was last Tuesday quiet" and "are Tuesdays quiet" — and only the
        second one changes when a venue opens.
        """
        served = bookings.filter(status__in=SERVED)

        totals = served.aggregate(
            covers=Sum('party_size'), bookings=Count('id')
        )
        by_date = (
            served.annotate(day=TruncDate('datetime'))
            .values('day')
            .annotate(covers=Sum('party_size'), bookings=Count('id'))
            .order_by('day')
        )
        # Grouped in Python: the weekday numbering differs between databases,
        # and a chart whose Mondays move when the backend changes is worse
        # than a loop.
        weekdays = {i: {'covers': 0, 'bookings': 0} for i in range(7)}
        for row in by_date:
            slot = weekdays[row['day'].weekday()]
            slot['covers'] += row['covers'] or 0
            slot['bookings'] += row['bookings']

        return {
            'total': totals['covers'] or 0,
            'bookings': totals['bookings'],
            'average_party_size': (
                round(totals['covers'] / totals['bookings'], 1)
                if totals['bookings']
                else None
            ),
            'by_date': [
                {
                    'date': row['day'],
                    'covers': row['covers'] or 0,
                    'bookings': row['bookings'],
                }
                for row in by_date
            ],
            'by_weekday': [
                {
                    'weekday': index,
                    'covers': slot['covers'],
                    'bookings': slot['bookings'],
                }
                for index, slot in sorted(weekdays.items())
            ],
        }

    # --- Attendance -------------------------------------------------------

    def _attendance(self, bookings):
        """What happened to the tables that were held.

        Missed and cancelled are reported apart, and that is the whole point
        of the section. One is a stranger who never came and cost the venue a
        table it could have sold; the other is a customer who said so. A
        single "did not attend" figure adds them together and tells a merchant
        to distrust people who behaved well.
        """
        counts = bookings.aggregate(
            total=Count('id'),
            missed=Count('id', filter=Q(status=Reservation.Status.NO_SHOW)),
            cancelled=Count(
                'id', filter=Q(status=Reservation.Status.CANCELLED)
            ),
            served=Count('id', filter=Q(status__in=SERVED)),
        )

        return {
            **counts,
            'missed_rate': _rate(counts['missed'], counts['total']),
            'cancelled_rate': _rate(counts['cancelled'], counts['total']),
            # Covers held that never sat, either way. Useful as one number
            # for "how much of the room did I hold for nobody", which is a
            # different question from why.
            'unfilled_rate': _rate(
                counts['missed'] + counts['cancelled'], counts['total']
            ),
        }

    # --- Peak hours -------------------------------------------------------

    def _peak_hours(self, bookings):
        """When the room fills, by the hour a booking is for.

        Every hour the venue had a booking in appears; hours it never did are
        left out rather than sent as zeroes. A lounge that opens at 17:00 does
        not want a chart whose first two thirds are empty by construction.
        """
        rows = (
            bookings.filter(status__in=SERVED)
            .annotate(hour=ExtractHour('datetime'))
            .values('hour')
            .annotate(bookings=Count('id'), covers=Sum('party_size'))
            .order_by('hour')
        )
        return [
            {
                'hour': row['hour'],
                'bookings': row['bookings'],
                'covers': row['covers'] or 0,
            }
            for row in rows
        ]

    # --- Dishes -----------------------------------------------------------

    def _dishes(self, establishment, start, end):
        """What sells, ranked two ways, because they disagree.

        By quantity is what the kitchen prepares most. By revenue is what pays
        for the kitchen. A venue whose top dish by quantity is missing from the
        top by revenue is selling a lot of something cheap, which is worth
        knowing and invisible from either list alone.

        Priced from `unit_price_at_order`, never from the menu today: what a
        dish earned last month is what it was sold for last month.
        """
        items = OrderItem.objects.filter(
            order__establishment=establishment,
            order__pickup_time__gte=start,
            order__pickup_time__lte=end,
        ).exclude(order__status=Order.Status.CANCELLED)

        ranked = (
            items.values('menu_item', 'menu_item__name')
            # `sold`, not `quantity`: an annotation named after the field it
            # sums shadows that field, and the revenue expression below would
            # then be multiplying by its own total.
            .annotate(
                sold=Sum('quantity'),
                revenue=Sum(
                    F('quantity') * F('unit_price_at_order'),
                    output_field=DecimalField(max_digits=14, decimal_places=2),
                ),
            )
            .filter(sold__gt=0)
        )

        def shape(rows):
            return [
                {
                    'id': row['menu_item'],
                    'name': row['menu_item__name'],
                    'quantity': row['sold'],
                    # A string, like every other amount in this API: nobody
                    # downstream rounds money.
                    'revenue': f'{row["revenue"]:.2f}',
                }
                for row in rows
            ]

        return {
            'by_quantity': shape(ranked.order_by('-sold')[:TOP_DISHES]),
            'by_revenue': shape(ranked.order_by('-revenue')[:TOP_DISHES]),
        }

    # --- Repeat customers -------------------------------------------------

    def _repeat_customers(self, establishment, bookings):
        """How much of the room is people who have been before.

        Identified by phone number, not by account. Accounts are optional and
        most customers here will never make one, so counting only signed-in
        regulars would report a venue's loyalty as near zero and be wrong
        about it.

        "Before" means before this booking, not before the window — otherwise
        a regular of three years reads as new every time the window moves.
        """
        served = bookings.filter(status__in=SERVED).exclude(customer_phone='')
        in_window = list(
            served.values_list('customer_phone', 'datetime').order_by(
                'datetime'
            )
        )
        if not in_window:
            return {
                'bookings': 0,
                'returning_bookings': 0,
                'returning_rate': None,
                'returning_customers': 0,
            }

        phones = {phone for phone, _ in in_window}
        firsts = self._first_visits(establishment, phones)
        returning = [
            phone
            for phone, when in in_window
            if firsts.get(phone) is not None and when > firsts[phone]
        ]

        return {
            'bookings': len(in_window),
            'returning_bookings': len(returning),
            'returning_rate': _rate(len(returning), len(in_window)),
            'returning_customers': len(set(returning)),
        }

    def _first_visits(self, establishment, phones):
        """The earliest booking each number ever made at this venue.

        Deliberately unbounded by the window: a regular of three years must
        not read as a new customer every time the window moves.
        """
        return {
            row['customer_phone']: row['first']
            for row in Reservation.objects.filter(
                space__establishment=establishment,
                customer_phone__in=phones,
            )
            .exclude(status=Reservation.Status.CANCELLED)
            .values('customer_phone')
            .annotate(first=Min('datetime'))
        }
