"""Optional accounts for customers, and the things an account carries.

The app works without one and always has: a booking or an order is proved by
its unguessable reference, kept on the phone. An account adds two things and
only two — the list survives losing the phone, and favourites become portable.

So nothing here gates the booking flow. Everything is additive.
"""

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from orders.models import Order
from rest_framework import serializers, status
from rest_framework.authtoken.models import Token
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.favourites import Favourite
from establishments.models import Establishment
from reservations.models import Reservation

from .order_serializers import OrderSerializer
from .serializers import EstablishmentListSerializer, ReservationSerializer

User = get_user_model()


class CustomerSerializer(serializers.ModelSerializer):
    """Who is signed in, on the customer side.

    Deliberately not the merchant serializer: a customer has no venues, and
    sending them an empty `establishments` list every request invites the app
    to ask what it would mean if it were not empty.
    """

    name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'username', 'name']
        read_only_fields = fields

    def get_name(self, user):
        return user.get_full_name() or user.first_name or user.username


class RegisterSerializer(serializers.Serializer):
    """Enough to come back to: a handle, a password, and a name to greet."""

    username = serializers.CharField(max_length=150)
    password = serializers.CharField(min_length=8, write_only=True)
    name = serializers.CharField(max_length=200, required=False, allow_blank=True)

    def validate_username(self, username):
        username = username.strip()
        if User.objects.filter(username__iexact=username).exists():
            raise serializers.ValidationError(
                'That name is taken. Try another, or sign in instead.'
            )
        return username

    def validate_password(self, password):
        # A deliberately low bar, checked here rather than through Django's
        # validators: this is a phone keyboard in a lounge, and a rule that
        # demands punctuation gets a password written on the receipt.
        if password.strip() != password:
            raise serializers.ValidationError(
                'Passwords cannot start or end with a space.'
            )
        return password


class RegisterView(APIView):
    """Make an account. Returns a token, so signup signs you in."""

    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        form = RegisterSerializer(data=request.data)
        form.is_valid(raise_exception=True)
        data = form.validated_data

        try:
            with transaction.atomic():
                user = User.objects.create_user(
                    username=data['username'],
                    password=data['password'],
                    first_name=data.get('name', '')[:150],
                )
        except IntegrityError:
            # Two signups racing for the same name. The loser is told the same
            # thing the validator would have said.
            raise serializers.ValidationError(
                {'username': 'That name is taken. Try another.'}
            ) from None

        token, _ = Token.objects.get_or_create(user=user)
        return Response(
            {'token': token.key, 'user': CustomerSerializer(user).data},
            status=status.HTTP_201_CREATED,
        )


class CustomerMeView(APIView):
    """Check a stored token still works, and get the name back."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(CustomerSerializer(request.user).data)


class ClaimView(APIView):
    """Attach this phone's bookings and orders to the account.

    Called once, straight after signing up or in. A reference is proof of
    ownership everywhere else in this API, so it is proof enough here — and
    anything already claimed by somebody else is skipped rather than stolen.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        references = request.data.get('reservation_references') or []
        order_references = request.data.get('order_references') or []

        claimed_bookings = Reservation.objects.filter(
            reference__in=references, customer__isnull=True
        ).update(customer=request.user)
        claimed_orders = Order.objects.filter(
            reference__in=order_references, customer__isnull=True
        ).update(customer=request.user)

        return Response(
            {
                'reservations': claimed_bookings,
                'orders': claimed_orders,
            }
        )


class CustomerHistoryView(APIView):
    """Everything this account has ever booked or ordered.

    What an account buys: this list survives a lost phone, where the local one
    does not.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        reservations = (
            Reservation.objects.filter(customer=request.user)
            .select_related('space__establishment')
            .prefetch_related('payments')
            .order_by('-datetime')
        )
        orders = (
            Order.objects.filter(customer=request.user)
            .select_related('establishment', 'reservation')
            .prefetch_related('items__menu_item', 'payments')
            .order_by('-pickup_time')
        )

        return Response(
            {
                'reservations': ReservationSerializer(
                    reservations, many=True
                ).data,
                'orders': OrderSerializer(orders, many=True).data,
            }
        )


class FavouritesView(APIView):
    """The venues this account has saved."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        establishments = Establishment.objects.filter(
            favourited_by__user=request.user
        ).order_by('-favourited_by__created_at')

        return Response(
            {
                'results': EstablishmentListSerializer(
                    establishments, many=True, context={'request': request}
                ).data
            }
        )

    def post(self, request):
        """Save one venue, or merge a whole list up from a phone.

        Takes `establishment` for a single tap, or `establishments` for the
        sync that runs when someone signs in with a list already on the
        device. Merging rather than replacing: signing in on a second phone
        must add to the list, never overwrite it with whatever that phone
        happened to have.
        """
        ids = request.data.get('establishments')
        if ids is None:
            single = request.data.get('establishment')
            if single is None:
                raise serializers.ValidationError(
                    {'establishment': 'Say which venue to save.'}
                )
            ids = [single]

        existing = set(
            Establishment.objects.filter(pk__in=ids).values_list('pk', flat=True)
        )
        Favourite.objects.bulk_create(
            [
                Favourite(user=request.user, establishment_id=pk)
                for pk in existing
            ],
            # The unique constraint is the real guard; this keeps a repeat tap
            # from being an error rather than a no-op.
            ignore_conflicts=True,
        )

        return self.get(request)


class FavouriteDetailView(APIView):
    """Unsave one venue."""

    permission_classes = [IsAuthenticated]

    def delete(self, request, pk):
        Favourite.objects.filter(
            user=request.user, establishment_id=pk
        ).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
