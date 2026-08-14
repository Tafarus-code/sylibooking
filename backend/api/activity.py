"""How much has arrived since the merchant last looked.

The desk used to find out about a new booking only when somebody pulled to
refresh, which is not how a service works. Push notifications are a later
slice — they need Firebase and a signing story — so in the meantime the app
asks this, often and cheaply, and shows a marker when the answer is not zero.

Counts only, deliberately. The app already knows how to fetch the lists; what
it lacks is a reason to. Sending the rows here would mean the same data twice
and a decision about which copy is authoritative.
"""

from django.utils import timezone
from orders.models import Order
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.permissions import (
    get_establishment_or_404,
    require_operations_access,
)
from reservations.models import Reservation


class MerchantActivityView(APIView):
    """GET /api/merchant/activity/?establishment=&since=

    `since` is an ISO timestamp, normally the moment the desk last loaded.
    Without it the answer is zero rather than everything: a client that has
    not told us where it got to is not asking a question we can answer.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        establishment_id = request.query_params.get('establishment')
        if not establishment_id:
            return Response(
                {'establishment': 'Required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        establishment = get_establishment_or_404(establishment_id)
        require_operations_access(request.user, establishment)

        raw_since = request.query_params.get('since')
        since = _parse(raw_since)
        if since is None:
            return Response(
                {'reservations': 0, 'orders': 0, 'total': 0, 'since': None}
            )

        reservations = Reservation.objects.filter(
            space__establishment=establishment,
            created_at__gt=since,
        ).count()
        orders = Order.objects.filter(
            establishment=establishment,
            created_at__gt=since,
        ).count()

        return Response(
            {
                'reservations': reservations,
                'orders': orders,
                'total': reservations + orders,
                'since': since,
            }
        )


def _parse(raw):
    if not raw:
        return None
    try:
        parsed = timezone.datetime.fromisoformat(raw)
    except ValueError:
        return None
    # A naive timestamp is taken as venue-local rather than refused: the app
    # sends UTC, but a hand-made request should not 500.
    if timezone.is_naive(parsed):
        parsed = timezone.make_aware(parsed)
    return parsed
