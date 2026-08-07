"""The dishes feed: what is worth eating tonight, across every venue.

The rest of the customer app asks "which venue?" first and "what do they
serve?" second. That is the wrong order for half the market — somebody who
wants yassa does not care whose kitchen it comes from, and a lounge's chicha
flavours are a reason to pick the lounge rather than a detail found after
picking it.

So this endpoint inverts the catalogue: menu items first, each carrying the
venue it belongs to, so tapping one lands on that venue's own screen with its
own branding already applied.

Deliberately a small, curated set rather than every item on the platform. A
venue marks its best few as featured; an un-curated feed of every price on
every menu is a spreadsheet, not a shop window.
"""

from rest_framework import serializers
from rest_framework.generics import ListAPIView
from rest_framework.permissions import AllowAny

from establishments.models import MenuItem

from .throttling import BrowseThrottle


class FeaturedItemSerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()
    establishment_name = serializers.CharField(
        source='establishment.name', read_only=True
    )
    establishment_type = serializers.CharField(
        source='establishment.type', read_only=True
    )
    city = serializers.CharField(source='establishment.city', read_only=True)

    class Meta:
        model = MenuItem
        fields = [
            'id',
            'name',
            'description',
            'price',
            'image',
            'category',
            'establishment',
            'establishment_name',
            'establishment_type',
            'city',
        ]
        read_only_fields = fields

    def get_image(self, item):
        if not item.image:
            return None
        request = self.context.get('request')
        return (
            request.build_absolute_uri(item.image.url)
            if request
            else item.image.url
        )


class FeaturedItemsView(ListAPIView):
    """Featured dishes across venues, newest venue-side first.

    Throttled with the browse ceiling rather than its own: it is the same
    catalogue seen from a different angle, and a scraper pulling this instead
    of the venue list should not find a cheaper door.
    """

    permission_classes = [AllowAny]
    throttle_classes = [BrowseThrottle]
    serializer_class = FeaturedItemSerializer

    def get_queryset(self):
        # Unavailable items are hidden rather than deleted elsewhere in this
        # app, and a sold-out dish in a shop window is a wasted tap.
        queryset = (
            MenuItem.objects.filter(is_featured=True, is_available=True)
            .select_related('establishment')
            .order_by('establishment__name', 'name')
        )

        city = self.request.query_params.get('city')
        if city:
            queryset = queryset.filter(establishment__city__iexact=city)

        type_ = self.request.query_params.get('type')
        if type_:
            queryset = queryset.filter(establishment__type=type_)

        return queryset
