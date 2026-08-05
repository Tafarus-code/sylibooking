"""What customers said, for the venue they said it about.

A merchant could not see their own reviews at all. Restaurants and lounges
live or die on this, and one that cannot read them in the app will read them
on Facebook instead — where nobody can flag anything and the platform hears
about a problem last.

**A merchant may flag, and may not hide.** A venue that can delete its own bad
reviews has a ratings system worth nothing to the customers it is meant to
inform, and the cost of that lands on the platform rather than the venue. So
flagging says "please look at this" and changes nothing a customer sees; only
an admin sets `is_hidden`.
"""

from django.db.models import Count
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.models import Review
from establishments.permissions import (
    get_establishment_or_404,
    require_operations_access,
    require_profile_access,
)

from .reviews import _Pagination


class MerchantReviewSerializer(serializers.ModelSerializer):
    """A review as its own venue sees it.

    Carries the moderation state the customer payload deliberately omits, so
    a merchant can tell "we asked about this" from "nobody has looked yet".
    """

    author_display_name = serializers.CharField(read_only=True)
    is_flagged = serializers.SerializerMethodField()
    visit_date = serializers.DateTimeField(
        source='reservation.datetime', read_only=True
    )

    class Meta:
        model = Review
        fields = [
            'id',
            'rating',
            'comment',
            'author_display_name',
            'visit_date',
            'created_at',
            'is_flagged',
            'flagged_at',
            'flagged_reason',
            'is_hidden',
        ]
        read_only_fields = fields

    def get_is_flagged(self, review):
        return review.flagged_at is not None


class MerchantReviewsView(APIView):
    """GET every review of this venue, hidden ones included and marked.

    Any member may read them: knowing what customers said is floor knowledge,
    not an owner's privilege.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        establishment = get_establishment_or_404(pk)
        require_operations_access(request.user, establishment)

        queryset = (
            Review.objects.filter(establishment=establishment)
            .select_related('reservation')
            .order_by('-created_at', '-id')
        )

        # The spread, which is what a merchant actually reads a review page
        # for: one angry two-star among forty fives is a different business
        # from a steady drift downwards.
        counts = {
            row['rating']: row['n']
            for row in Review.objects.filter(
                establishment=establishment, is_hidden=False
            )
            .values('rating')
            .annotate(n=Count('id'))
        }

        paginator = _Pagination()
        page = paginator.paginate_queryset(queryset, request, view=self)
        response = paginator.get_paginated_response(
            MerchantReviewSerializer(page, many=True).data
        )
        response.data['average_rating'] = establishment.average_rating
        response.data['distribution'] = {
            str(star): counts.get(star, 0) for star in range(1, 6)
        }
        return response


class MerchantReviewFlagView(APIView):
    """POST a reason for an admin to look at one review.

    Owner and manager: disputing what a customer said is a decision about how
    the venue answers the public, which is the same class of thing as its
    description or its branding.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request, pk, review_id):
        establishment = get_establishment_or_404(pk)
        require_profile_access(request.user, establishment)

        try:
            review = Review.objects.get(pk=review_id, establishment=establishment)
        except Review.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        reason = (request.data.get('reason') or '').strip()
        if not reason:
            return Response(
                {'reason': 'Say what is wrong with it.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if review.flagged_at is not None:
            return Response(
                {'detail': 'That review has already been flagged.'},
                status=status.HTTP_409_CONFLICT,
            )

        review.flagged_at = timezone.now()
        review.flagged_reason = reason[:2000]
        review.save(update_fields=['flagged_at', 'flagged_reason'])

        return Response(MerchantReviewSerializer(review).data)
