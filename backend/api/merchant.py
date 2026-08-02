"""Merchant-facing endpoints: venues, profile, hours, menu and staff.

Every one takes an establishment id in the path and checks membership against
that id. Nothing here relies on the caller having exactly one venue, and
nothing relies on the UI having hidden a button.
"""

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.db.models import ProtectedError
from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.models import (
    Establishment,
    MenuItem,
    MerchantMembership,
    OpeningHours,
    Space,
)
from establishments.permissions import (
    get_establishment_or_404,
    memberships_of,
    require_operations_access,
    require_profile_access,
    require_staff_management,
)
from establishments.theme_presets import DEFAULT_PRESET, PRESETS

from .reviews import validate_photo_file  # noqa: E402  (after app imports)
from .serializers import SpaceWriteSerializer  # noqa: E402

User = get_user_model()


# --- Serializers ---------------------------------------------------------


class MembershipEstablishmentSerializer(serializers.ModelSerializer):
    """A venue as it appears in the caller's own venue list."""

    role = serializers.SerializerMethodField()
    role_display = serializers.SerializerMethodField()
    can_edit_profile = serializers.SerializerMethodField()
    can_manage_staff = serializers.SerializerMethodField()

    class Meta:
        model = Establishment
        fields = [
            'id',
            'name',
            'type',
            'city',
            'address',
            'tagline',
            # The merchant app themes a venue's own screens with its chosen
            # preset, so it has to know the preset from the venue list rather
            # than fetching each profile to find out.
            'theme_preset',
            'role',
            'role_display',
            'can_edit_profile',
            'can_manage_staff',
        ]

    def _membership(self, establishment):
        return self.context['roles'][establishment.id]

    def get_role(self, establishment):
        return self._membership(establishment).role

    def get_role_display(self, establishment):
        return self._membership(establishment).get_role_display()

    def get_can_edit_profile(self, establishment):
        return self._membership(establishment).can_edit_profile

    def get_can_manage_staff(self, establishment):
        return self._membership(establishment).can_manage_staff


class EstablishmentProfileSerializer(serializers.ModelSerializer):
    """The venue's own details, editable by owners and managers."""

    class Meta:
        model = Establishment
        fields = [
            'id',
            'name',
            'type',
            'city',
            'address',
            'latitude',
            'longitude',
            'tagline',
            'description',
            'opening_hours',
            'theme_preset',
        ]


class OpeningHoursWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = OpeningHours
        fields = ['day_of_week', 'is_closed', 'opens', 'closes']

    def validate(self, attrs):
        if not attrs.get('is_closed'):
            if attrs.get('opens') is None or attrs.get('closes') is None:
                raise serializers.ValidationError(
                    'A day that is not closed needs both an opening and a '
                    'closing time.'
                )
        return attrs


class MenuItemWriteSerializer(serializers.ModelSerializer):
    """Menu item, image included.

    The image is optional everywhere: most items will never have one, and a
    merchant on a slow connection should not be blocked from adding a dish
    because a photo will not upload.
    """

    image = serializers.ImageField(
        required=False,
        allow_null=True,
        validators=[validate_photo_file],
    )
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = MenuItem
        fields = [
            'id',
            'name',
            'description',
            'category',
            'price',
            'is_available',
            'image',
            'image_url',
        ]
        read_only_fields = ['id', 'image_url']
        extra_kwargs = {'image': {'write_only': True}}

    def get_image_url(self, item):
        if not item.image:
            return None
        request = self.context.get('request')
        return (
            request.build_absolute_uri(item.image.url)
            if request
            else item.image.url
        )


class MembershipSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username', read_only=True)
    full_name = serializers.SerializerMethodField()
    role_display = serializers.CharField(
        source='get_role_display', read_only=True
    )

    class Meta:
        model = MerchantMembership
        fields = [
            'id',
            'user',
            'username',
            'full_name',
            'role',
            'role_display',
            'created_at',
        ]
        read_only_fields = ['id', 'user', 'created_at']

    def get_full_name(self, membership):
        return membership.user.get_full_name() or membership.user.username


# --- Venue list and creation ---------------------------------------------


class MerchantEstablishmentsView(APIView):
    """GET the caller's venues with their role; POST to create one."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        memberships = memberships_of(request.user)
        roles = {m.establishment_id: m for m in memberships}
        establishments = [m.establishment for m in memberships]

        # A superuser holds no membership rows, so they would otherwise see an
        # empty list despite having access to everything.
        if request.user.is_superuser and not establishments:
            establishments = list(Establishment.objects.all())
            roles = {
                e.id: MerchantMembership(
                    user=request.user,
                    establishment=e,
                    role=MerchantMembership.Role.OWNER,
                )
                for e in establishments
            }

        serializer = MembershipEstablishmentSerializer(
            establishments, many=True, context={'roles': roles}
        )
        return Response({'results': serializer.data})

    def post(self, request):
        """Create a venue. The creator becomes its owner."""
        serializer = EstablishmentProfileSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        with transaction.atomic():
            establishment = serializer.save()
            MerchantMembership.objects.create(
                user=request.user,
                establishment=establishment,
                role=MerchantMembership.Role.OWNER,
            )

        return Response(
            EstablishmentProfileSerializer(establishment).data,
            status=status.HTTP_201_CREATED,
        )


class MerchantSpacesView(APIView):
    """GET every space including deactivated ones; POST to add one.

    Staff read this — the desk shows which table a booking is on — but only
    owners and managers change it. A room's layout is structural, the same
    class of decision as opening hours.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_operations_access(request.user, establishment)
        return Response(
            {
                'results': SpaceWriteSerializer(
                    establishment.spaces.all(), many=True
                ).data
            }
        )

    def post(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        serializer = SpaceWriteSerializer(
            data=request.data, context={'establishment': establishment}
        )
        serializer.is_valid(raise_exception=True)
        serializer.save(establishment=establishment)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class MerchantSpaceItemView(APIView):
    """PATCH one space, or take it out of service. Owner and manager only."""

    permission_classes = [IsAuthenticated]

    def get_space(self, establishment, space_id):
        # Scoped to the establishment in the path, so a space id belonging to
        # another venue is a 404 rather than someone else's table.
        return get_object_or_404(Space, pk=space_id, establishment=establishment)

    def patch(self, request, pk, space_id):
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        space = self.get_space(establishment, space_id)
        serializer = SpaceWriteSerializer(
            space,
            data=request.data,
            partial=True,
            context={'establishment': establishment},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, pk, space_id):
        """Remove the space if nothing was ever booked on it; else retire it.

        `Reservation.space` is PROTECT, so the database refuses to delete a
        space with history — that refusal is the real guard, not this check.
        A venue's past bookings name the table they were on, and a merchant
        rearranging their room must not silently rewrite last month.

        204 means the row is gone. 200 with the space means it was retired
        instead, so the app can tell the merchant which of the two happened.
        """
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)
        space = self.get_space(establishment, space_id)

        try:
            space.delete()
        except ProtectedError:
            space.is_active = False
            space.save(update_fields=['is_active'])
            return Response(SpaceWriteSerializer(space).data)

        return Response(status=status.HTTP_204_NO_CONTENT)


class ThemePresetsView(APIView):
    """GET /api/theme-presets/ — the curated set, for the branding screen.

    Served rather than hard-coded in the app so a preset can be corrected
    without shipping a new build, and so both apps and the backend agree on
    one definition.
    """

    permission_classes = [AllowAny]

    def get(self, request):
        return Response({'default': DEFAULT_PRESET, 'results': PRESETS})


class MerchantEstablishmentProfileView(APIView):
    """GET and PATCH one venue's profile. Owner and manager only."""

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_operations_access(request.user, establishment)
        return Response(EstablishmentProfileSerializer(establishment).data)

    def patch(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        serializer = EstablishmentProfileSerializer(
            establishment, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


# --- Hours ----------------------------------------------------------------


class MerchantHoursView(APIView):
    """GET the week; PUT to replace it. Owner and manager only."""

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_operations_access(request.user, establishment)
        rows = establishment.hours.all()
        return Response(
            {'results': OpeningHoursWriteSerializer(rows, many=True).data}
        )

    def put(self, request, pk):
        """Replace the whole week in one call.

        A week is edited as a unit — seven partial updates would leave the
        venue in states it was never meant to be in halfway through.
        """
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        serializer = OpeningHoursWriteSerializer(data=request.data, many=True)
        serializer.is_valid(raise_exception=True)

        days = [row['day_of_week'] for row in serializer.validated_data]
        if len(set(days)) != len(days):
            raise serializers.ValidationError(
                {'day_of_week': 'Each weekday may appear only once.'}
            )

        with transaction.atomic():
            establishment.hours.all().delete()
            OpeningHours.objects.bulk_create(
                [
                    OpeningHours(establishment=establishment, **row)
                    for row in serializer.validated_data
                ]
            )

        rows = establishment.hours.all()
        return Response(
            {'results': OpeningHoursWriteSerializer(rows, many=True).data}
        )


# --- Menu -----------------------------------------------------------------


class MerchantMenuView(APIView):
    """GET every item including unavailable ones; POST to add one."""

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        establishment = get_establishment_or_404(pk)
        # Staff need to read the menu to toggle availability on it.
        require_operations_access(request.user, establishment)
        items = establishment.menu_items.all()
        return Response(
            {
                'results': MenuItemWriteSerializer(
                    items, many=True, context={'request': request}
                ).data
            }
        )

    def post(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        serializer = MenuItemWriteSerializer(
            data=request.data, context={'request': request}
        )
        serializer.is_valid(raise_exception=True)
        serializer.save(establishment=establishment)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class MerchantMenuItemView(APIView):
    """PATCH or DELETE one item. Owner and manager only."""

    permission_classes = [IsAuthenticated]

    def get_item(self, establishment, item_id):
        return get_object_or_404(
            MenuItem, pk=item_id, establishment=establishment
        )

    def patch(self, request, pk, item_id):
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        item = self.get_item(establishment, item_id)
        serializer = MenuItemWriteSerializer(
            item,
            data=request.data,
            partial=True,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, pk, item_id):
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        self.get_item(establishment, item_id).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class MerchantMenuAvailabilityView(APIView):
    """PATCH one item's availability. Every role, staff included.

    The deliberate exception to profile editing: marking a dish sold out is a
    floor decision taken mid-service, and routing it through a manager would
    mean customers ordering things the kitchen has run out of.
    """

    permission_classes = [IsAuthenticated]

    def patch(self, request, pk, item_id):
        establishment = get_establishment_or_404(pk)
        require_operations_access(request.user, establishment)

        item = get_object_or_404(
            MenuItem, pk=item_id, establishment=establishment
        )

        if 'is_available' not in request.data:
            raise serializers.ValidationError(
                {'is_available': 'Required. Send true or false.'}
            )

        item.is_available = bool(request.data['is_available'])
        item.save(update_fields=['is_available'])
        return Response(
            MenuItemWriteSerializer(item, context={'request': request}).data
        )


# --- Staff ----------------------------------------------------------------


class MerchantStaffView(APIView):
    """GET the member list; POST to add one. Owner only."""

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_staff_management(request.user, establishment)

        memberships = establishment.memberships.select_related('user')
        return Response(
            {'results': MembershipSerializer(memberships, many=True).data}
        )

    def post(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_staff_management(request.user, establishment)

        username = request.data.get('username')
        role = request.data.get('role', MerchantMembership.Role.STAFF)

        if not username:
            raise serializers.ValidationError(
                {'username': 'Required — who are you adding?'}
            )
        if role not in MerchantMembership.Role.values:
            raise serializers.ValidationError(
                {'role': f'Must be one of {", ".join(MerchantMembership.Role.values)}.'}
            )

        user = User.objects.filter(username=username).first()
        if user is None:
            raise serializers.ValidationError(
                {'username': f'No user called "{username}".'}
            )

        try:
            membership = MerchantMembership.objects.create(
                user=user, establishment=establishment, role=role
            )
        except IntegrityError:
            raise serializers.ValidationError(
                {'username': f'{username} already has access here.'}
            ) from None

        return Response(
            MembershipSerializer(membership).data,
            status=status.HTTP_201_CREATED,
        )


class MerchantStaffMemberView(APIView):
    """PATCH a member's role or DELETE their access. Owner only."""

    permission_classes = [IsAuthenticated]

    def get_membership(self, establishment, membership_id):
        return get_object_or_404(
            MerchantMembership, pk=membership_id, establishment=establishment
        )

    def patch(self, request, pk, membership_id):
        establishment = get_establishment_or_404(pk)
        caller = require_staff_management(request.user, establishment)

        membership = self.get_membership(establishment, membership_id)
        role = request.data.get('role')
        if role not in MerchantMembership.Role.values:
            raise serializers.ValidationError(
                {'role': f'Must be one of {", ".join(MerchantMembership.Role.values)}.'}
            )

        # Refuse to leave a venue with nobody who can manage access.
        if (
            membership.role == MerchantMembership.Role.OWNER
            and role != MerchantMembership.Role.OWNER
            and self._other_owners(establishment, membership).count() == 0
        ):
            raise serializers.ValidationError(
                {
                    'role': (
                        'This is the only owner. Promote someone else first, '
                        'or the venue would be left with nobody who can '
                        'manage access.'
                    )
                }
            )

        membership.role = role
        membership.save(update_fields=['role'])
        # Caller may have just demoted themselves; that is allowed, but only
        # because another owner remains.
        del caller
        return Response(MembershipSerializer(membership).data)

    def delete(self, request, pk, membership_id):
        establishment = get_establishment_or_404(pk)
        require_staff_management(request.user, establishment)

        membership = self.get_membership(establishment, membership_id)
        if (
            membership.role == MerchantMembership.Role.OWNER
            and self._other_owners(establishment, membership).count() == 0
        ):
            raise serializers.ValidationError(
                {
                    'detail': (
                        'This is the only owner. Removing them would leave '
                        'the venue with nobody who can manage access.'
                    )
                }
            )

        membership.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @staticmethod
    def _other_owners(establishment, membership):
        return establishment.memberships.filter(
            role=MerchantMembership.Role.OWNER
        ).exclude(pk=membership.pk)
