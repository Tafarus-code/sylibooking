"""The handful of numbers that say whether the product is working.

Not a general metrics system. Four questions, each chosen because its answer
is invisible from inside the app and expensive to learn late:

  * **Are bookings still being made?** A drop is the first sign of an outage
    the merchants have not phoned about yet.
  * **Do payments that start also finish?** The gap between initiated and
    completed is where mobile money fails quietly — the customer sees a
    prompt that never resolves and simply gives up.
  * **Do notifications arrive?** This one is silent by construction: nobody
    complains about a reminder they never expected. Slice 7's log exists so
    that this ratio can be read at all.
  * **Are the ceilings being hit?** Slice 19 set rates it admitted were
    guesses, deliberately loose, to be tuned once there was traffic to look
    at. This is what makes that possible.

Read over a window rather than since-the-beginning-of-time: a lifetime total
hides today, and today is the only thing anybody acts on.
"""

from datetime import timedelta

from django.db.models import Count, Q
from django.utils import timezone
from notifications.models import Notification
from orders.models import Order
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from payments.models import Payment
from reservations.models import Reservation

#: How far back the numbers look, unless asked otherwise.
DEFAULT_WINDOW_HOURS = 24

#: Beyond this the query stops being cheap and the answer stops being about
#: right now.
MAX_WINDOW_HOURS = 24 * 30


def _ratio(part, whole):
    """A share, or None when there is nothing to take a share of.

    None rather than 0.0 on purpose: a delivery rate of zero means every
    message failed, and an hour when nothing was sent must not raise the
    same alarm.
    """
    return None if not whole else round(part / whole, 4)


def collect(since):
    """Every number, for one window. Pure, so a test can read it directly."""
    bookings = Reservation.objects.filter(created_at__gte=since)
    payments = Payment.objects.filter(created_at__gte=since)
    notifications = Notification.objects.filter(created_at__gte=since)

    payment_counts = payments.aggregate(
        started=Count('id'),
        completed=Count('id', filter=Q(status=Payment.Status.COMPLETED)),
        failed=Count('id', filter=Q(status=Payment.Status.FAILED)),
        pending=Count('id', filter=Q(status=Payment.Status.PENDING)),
    )
    notification_counts = notifications.aggregate(
        attempted=Count('id'),
        sent=Count('id', filter=Q(status=Notification.Status.SENT)),
        failed=Count('id', filter=Q(status=Notification.Status.FAILED)),
    )

    return {
        'bookings': {
            'created': bookings.count(),
            'cancelled': bookings.filter(
                status=Reservation.Status.CANCELLED
            ).count(),
            # The sweep's own output. A jump here is either a bad night or a
            # no-show window set too tight.
            'no_show': bookings.filter(
                status=Reservation.Status.NO_SHOW
            ).count(),
        },
        'orders': {'created': Order.objects.filter(created_at__gte=since).count()},
        'payments': {
            **payment_counts,
            # The number to watch. Money that starts and does not finish is
            # a customer who tried to pay and could not.
            'completion_rate': _ratio(
                payment_counts['completed'], payment_counts['started']
            ),
            # Still pending at the end of the window, which after the
            # abandon cut-off means the poller is not keeping up.
            'stuck': payments.filter(
                status=Payment.Status.PENDING,
                created_at__lt=timezone.now()
                - timedelta(minutes=DEFAULT_WINDOW_HOURS * 60),
            ).count(),
        },
        'notifications': {
            **notification_counts,
            'delivery_rate': _ratio(
                notification_counts['sent'], notification_counts['attempted']
            ),
        },
    }


class MetricsView(APIView):
    """Admin only.

    These numbers say how much money moved and how many people came, which
    is a venue's business and not a public fact — and in aggregate it is the
    platform's own trading position.
    """

    permission_classes = [IsAdminUser]

    def get(self, request):
        try:
            hours = int(request.query_params.get('hours', DEFAULT_WINDOW_HOURS))
        except ValueError:
            hours = DEFAULT_WINDOW_HOURS
        hours = max(1, min(hours, MAX_WINDOW_HOURS))

        since = timezone.now() - timedelta(hours=hours)
        return Response({
            'window': {'hours': hours, 'since': since},
            **collect(since),
        })
