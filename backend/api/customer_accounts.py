"""Optional accounts for customers, and the things an account carries.

The app works without one and always has: a booking or an order is proved by
its unguessable reference, kept on the phone. An account adds two things and
only two — the list survives losing the phone, and favourites become portable.

So nothing here gates the booking flow. Everything is additive.
"""

from accounts.deletion import close_account, refusal_reason
from accounts.models import CustomerProfile
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.utils.translation import gettext as _
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
from .throttling import RegistrationThrottle

User = get_user_model()


class CustomerSerializer(serializers.ModelSerializer):
    """Who is signed in, on the customer side.

    Deliberately not the merchant serializer: a customer has no venues, and
    sending them an empty `establishments` list every request invites the app
    to ask what it would mean if it were not empty.
    """

    name = serializers.SerializerMethodField()
    # Sent so the profile form can show what is on file rather than an empty
    # box that looks like nothing was ever saved.
    phone = serializers.SerializerMethodField()
    email = serializers.CharField(read_only=True)
    # So the app can warn someone with no contact details that forgetting the
    # password would lock them out, while there is still time to add one.
    can_reset_password = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id',
            'username',
            'name',
            'phone',
            'email',
            'can_reset_password',
        ]
        read_only_fields = fields

    def get_phone(self, user):
        profile = getattr(user, 'customer_profile', None)
        return profile.phone if profile else ''

    def get_can_reset_password(self, user):
        profile = getattr(user, 'customer_profile', None)
        return bool(user.email or (profile and profile.phone))

    def get_name(self, user):
        return user.get_full_name() or user.first_name or user.username


class RegisterSerializer(serializers.Serializer):
    """Enough to come back to: a handle, a password, and a name to greet."""

    username = serializers.CharField(max_length=150)
    password = serializers.CharField(min_length=8, write_only=True)
    name = serializers.CharField(max_length=200, required=False, allow_blank=True)

    # Optional, but the only way back in if the password is forgotten — which
    # is why the app asks for one and says exactly what it is for.
    phone = serializers.CharField(max_length=30, required=False, allow_blank=True)
    email = serializers.EmailField(required=False, allow_blank=True)

    def validate_username(self, username):
        username = username.strip()
        if User.objects.filter(username__iexact=username).exists():
            raise serializers.ValidationError(
                _('That name is taken. Try another, or sign in instead.')
            )
        return username

    def validate_password(self, password):
        # A deliberately low bar, checked here rather than through Django's
        # validators: this is a phone keyboard in a lounge, and a rule that
        # demands punctuation gets a password written on the receipt.
        if password.strip() != password:
            raise serializers.ValidationError(
                _('Passwords cannot start or end with a space.')
            )
        return password


class RegisterView(APIView):
    """Make an account. Returns a token, so signup signs you in."""

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [RegistrationThrottle]

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
                    email=data.get('email', ''),
                )
                CustomerProfile.objects.create(
                    user=user, phone=data.get('phone', '').strip()
                )
        except IntegrityError:
            # Two signups racing for the same name. The loser is told the same
            # thing the validator would have said.
            raise serializers.ValidationError(
                {'username': _('That name is taken. Try another.')}
            ) from None

        # Not `_`: that name is gettext in this module, and rebinding it here
        # made the message above it an UnboundLocalError waiting to happen.
        token, _created = Token.objects.get_or_create(user=user)
        return Response(
            {'token': token.key, 'user': CustomerSerializer(user).data},
            status=status.HTTP_201_CREATED,
        )


class ProfileSerializer(serializers.Serializer):
    """The three things an account is allowed to change about itself.

    Not the username: it is what somebody signs in with, and letting it move
    turns "I cannot get in" into a support conversation nobody can settle.
    """

    name = serializers.CharField(max_length=200, required=False, allow_blank=True)
    phone = serializers.CharField(max_length=30, required=False, allow_blank=True)
    email = serializers.EmailField(required=False, allow_blank=True)


class CustomerMeView(APIView):
    """Who is signed in — read it, change it, or close it."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(CustomerSerializer(request.user).data)

    def patch(self, request):
        """Keep a returning customer's details current.

        Until now a name and a number were captured per booking and never
        maintained, so a customer who changed number had no way to say so
        except by typing it again on the next booking.
        """
        form = ProfileSerializer(data=request.data, partial=True)
        form.is_valid(raise_exception=True)
        data = form.validated_data

        user = request.user
        if 'name' in data:
            user.first_name = data['name'].strip()[:150]
        if 'email' in data:
            user.email = data['email'].strip()
        user.save(update_fields=['first_name', 'email'])

        if 'phone' in data:
            profile, _created = CustomerProfile.objects.get_or_create(user=user)
            profile.phone = data['phone'].strip()
            profile.save(update_fields=['phone'])

        return Response(CustomerSerializer(user).data)

    def delete(self, request):
        """Close the account.

        The password is asked for again because the token on this phone may
        not be in the hands of the person it belongs to, and this is the one
        action here that cannot be undone.

        What happens to the data is decided in accounts/deletion.py, which
        explains the trade — the person goes, the venue's books stay.
        """
        password = request.data.get('password') or ''
        if not request.user.check_password(password):
            return Response(
                {'password': _('That password is not right.')},
                status=status.HTTP_400_BAD_REQUEST,
            )

        refusal = refusal_reason(request.user)
        if refusal:
            return Response(
                {'detail': refusal}, status=status.HTTP_409_CONFLICT
            )

        close_account(request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)


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
                    {'establishment': _('Say which venue to save.')}
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
