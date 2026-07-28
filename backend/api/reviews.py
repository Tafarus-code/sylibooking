"""Reviews and photos: who may post one, and what the public sees.

Customers have no accounts, so the reservation reference issued at booking is
what proves someone actually visited. Merchants use their token. Both paths end
up in the same two endpoints.
"""

from django.conf import settings
from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.models import Establishment, Photo, Review
from reservations.models import Reservation


class ReviewSerializer(serializers.ModelSerializer):
    """What a customer browsing reviews sees.

    Deliberately no phone number and no surname: the booking holds both, and a
    public review needs neither.
    """

    author = serializers.CharField(source='author_display_name', read_only=True)

    class Meta:
        model = Review
        fields = ['id', 'rating', 'comment', 'author', 'created_at']
        read_only_fields = fields


class PhotoSerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()
    uploaded_by_role_display = serializers.CharField(
        source='get_uploaded_by_role_display', read_only=True
    )

    class Meta:
        model = Photo
        fields = [
            'id',
            'image',
            'caption',
            'uploaded_by_role',
            'uploaded_by_role_display',
            'created_at',
        ]
        read_only_fields = fields

    def get_image(self, photo):
        if not photo.image:
            return None
        request = self.context.get('request')
        url = photo.image.url
        return request.build_absolute_uri(url) if request else url


def validate_photo_file(uploaded):
    """Reject files that are too large, or that are not images at all.

    ImageField already refuses non-images at the model layer, but doing it
    here turns a 500 into a clear 400, and size has to be checked explicitly.
    """
    if uploaded.size > settings.MAX_PHOTO_UPLOAD_BYTES:
        limit_mb = settings.MAX_PHOTO_UPLOAD_BYTES / (1024 * 1024)
        raise serializers.ValidationError(
            f'That image is too large. The limit is {limit_mb:.0f} MB.'
        )

    name = (uploaded.name or '').lower()
    extension = name.rsplit('.', 1)[-1] if '.' in name else ''
    if extension not in settings.ALLOWED_PHOTO_EXTENSIONS:
        allowed = ', '.join(settings.ALLOWED_PHOTO_EXTENSIONS)
        raise serializers.ValidationError(
            f'Only {allowed} images are accepted.'
        )
    return uploaded


class ReviewCreateSerializer(serializers.Serializer):
    """Posting a review, proven by the reference from the booking."""

    reservation_reference = serializers.UUIDField(
        write_only=True,
        help_text=(
            'The reference issued when the booking was made. Customers have '
            'no accounts, so this is what proves the visit happened.'
        ),
    )
    rating = serializers.IntegerField(min_value=1, max_value=5)
    comment = serializers.CharField(
        required=False, allow_blank=True, max_length=2000
    )

    def __init__(self, *args, establishment=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.establishment = establishment

    def validate_reservation_reference(self, reference):
        reservation = Reservation.objects.filter(reference=reference).first()

        # One message for "no such booking" and "not your booking": a
        # different answer would let someone probe for valid references.
        if reservation is None or (
            reservation.space.establishment_id != self.establishment.id
        ):
            raise serializers.ValidationError(
                'No booking here matches that reference.'
            )

        if reservation.status != Reservation.Status.COMPLETED:
            raise serializers.ValidationError(
                'You can review a visit once it is complete. This booking is '
                f'{reservation.get_status_display().lower()}.'
            )

        if Review.objects.filter(reservation=reservation).exists():
            raise serializers.ValidationError(
                'This visit has already been reviewed.'
            )

        return reservation

    def create(self, validated_data):
        reservation = validated_data['reservation_reference']
        return Review.objects.create(
            establishment=self.establishment,
            reservation=reservation,
            rating=validated_data['rating'],
            comment=validated_data.get('comment', ''),
        )


class PhotoCreateSerializer(serializers.Serializer):
    """Posting a photo, from either a customer or the venue itself."""

    reservation_reference = serializers.UUIDField(
        required=False,
        write_only=True,
        help_text='Required for customers. Omitted by merchants.',
    )
    image = serializers.ImageField(validators=[validate_photo_file])
    caption = serializers.CharField(
        required=False, allow_blank=True, max_length=200
    )

    def __init__(self, *args, establishment=None, user=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.establishment = establishment
        self.user = user

    def _merchant_owns_establishment(self):
        if self.user is None or not self.user.is_authenticated:
            return False
        if self.user.is_superuser:
            return True
        return self.establishment.staff.filter(pk=self.user.pk).exists()

    def validate(self, attrs):
        reference = attrs.get('reservation_reference')

        if reference is not None:
            reservation = Reservation.objects.filter(reference=reference).first()
            if reservation is None or (
                reservation.space.establishment_id != self.establishment.id
            ):
                raise serializers.ValidationError(
                    {
                        'reservation_reference': (
                            'No booking here matches that reference.'
                        )
                    }
                )
            # Any status: someone who booked and was turned away still has
            # something to show.
            attrs['reservation'] = reservation
            attrs['uploaded_by_role'] = Photo.UploaderRole.CUSTOMER
            return attrs

        if self._merchant_owns_establishment():
            attrs['reservation'] = None
            attrs['uploaded_by_role'] = Photo.UploaderRole.MERCHANT
            return attrs

        raise serializers.ValidationError(
            {
                'reservation_reference': (
                    'Send the reference from your booking, or sign in as staff '
                    'of this establishment.'
                )
            }
        )

    def create(self, validated_data):
        return Photo.objects.create(
            establishment=self.establishment,
            reservation=validated_data['reservation'],
            uploaded_by_role=validated_data['uploaded_by_role'],
            image=validated_data['image'],
            caption=validated_data.get('caption', ''),
        )


class _Pagination(PageNumberPagination):
    page_size = 20


class EstablishmentReviewsView(APIView):
    """GET the visible reviews, POST a new one."""

    permission_classes = [AllowAny]

    def get_establishment(self, pk):
        return get_object_or_404(Establishment, pk=pk)

    def get(self, request, pk):
        establishment = self.get_establishment(pk)
        queryset = (
            Review.objects.filter(establishment=establishment, is_hidden=False)
            .select_related('reservation')
            .order_by('-created_at', '-id')
        )

        paginator = _Pagination()
        page = paginator.paginate_queryset(queryset, request, view=self)
        serializer = ReviewSerializer(page, many=True, context={'request': request})
        return paginator.get_paginated_response(serializer.data)

    def post(self, request, pk):
        establishment = self.get_establishment(pk)
        serializer = ReviewCreateSerializer(
            data=request.data, establishment=establishment
        )
        serializer.is_valid(raise_exception=True)
        review = serializer.save()
        return Response(
            ReviewSerializer(review, context={'request': request}).data,
            status=status.HTTP_201_CREATED,
        )


class EstablishmentPhotosView(APIView):
    """GET the visible photos, POST a new one."""

    permission_classes = [AllowAny]

    def get_establishment(self, pk):
        return get_object_or_404(Establishment, pk=pk)

    def get(self, request, pk):
        establishment = self.get_establishment(pk)
        queryset = Photo.objects.filter(
            establishment=establishment, is_hidden=False
        ).order_by('-created_at', '-id')

        paginator = _Pagination()
        page = paginator.paginate_queryset(queryset, request, view=self)
        serializer = PhotoSerializer(page, many=True, context={'request': request})
        return paginator.get_paginated_response(serializer.data)

    def post(self, request, pk):
        establishment = self.get_establishment(pk)
        serializer = PhotoCreateSerializer(
            data=request.data,
            establishment=establishment,
            user=request.user,
        )
        serializer.is_valid(raise_exception=True)
        photo = serializer.save()
        return Response(
            PhotoSerializer(photo, context={'request': request}).data,
            status=status.HTTP_201_CREATED,
        )
