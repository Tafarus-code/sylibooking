from django.contrib import admin

from .models import Establishment, MenuItem, OpeningHours, Photo, Review, Space


class SpaceInline(admin.TabularInline):
    """Add tables/rooms while creating the establishment, in one screen."""

    model = Space
    extra = 3


class OpeningHoursInline(admin.TabularInline):
    """Seven rows, one per weekday."""

    model = OpeningHours
    extra = 7
    max_num = 7


class MenuItemInline(admin.TabularInline):
    model = MenuItem
    extra = 3


@admin.register(Establishment)
class EstablishmentAdmin(admin.ModelAdmin):
    list_display = ['name', 'type', 'city', 'created_at']
    list_filter = ['type', 'city']
    search_fields = ['name', 'address']
    filter_horizontal = ['staff']
    inlines = [OpeningHoursInline, SpaceInline, MenuItemInline]


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    """Moderation surface: find bad content and hide it without deleting it."""

    list_display = [
        'establishment',
        'rating',
        'author_display_name',
        'short_comment',
        'created_at',
        'is_hidden',
    ]
    # Toggle straight from the list — moderation is a scan, not a click-through.
    list_editable = ['is_hidden']
    list_filter = ['is_hidden', 'rating', 'establishment', 'created_at']
    search_fields = ['comment', 'reservation__customer_name']
    list_select_related = ['establishment', 'reservation']
    # The visit and the score are facts; only visibility is the moderator's.
    readonly_fields = ['establishment', 'reservation', 'rating', 'created_at']
    actions = ['hide_reviews', 'unhide_reviews']

    @admin.display(description='Comment')
    def short_comment(self, review):
        if not review.comment:
            return '—'
        return (
            review.comment
            if len(review.comment) <= 60
            else f'{review.comment[:57]}…'
        )

    @admin.action(description='Hide selected reviews')
    def hide_reviews(self, request, queryset):
        updated = queryset.update(is_hidden=True)
        self.message_user(request, f'{updated} review(s) hidden.')

    @admin.action(description='Unhide selected reviews')
    def unhide_reviews(self, request, queryset):
        updated = queryset.update(is_hidden=False)
        self.message_user(request, f'{updated} review(s) restored.')


@admin.register(Photo)
class PhotoAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'establishment',
        'uploaded_by_role',
        'caption',
        'created_at',
        'is_hidden',
    ]
    list_editable = ['is_hidden']
    list_filter = ['is_hidden', 'uploaded_by_role', 'establishment', 'created_at']
    search_fields = ['caption']
    list_select_related = ['establishment']
    readonly_fields = ['image_preview', 'created_at', 'uploaded_by_role']
    actions = ['hide_photos', 'unhide_photos']

    @admin.display(description='Preview')
    def image_preview(self, photo):
        """Moderating photos without seeing them would be useless."""
        from django.utils.html import format_html

        if not photo.image:
            return '—'
        return format_html(
            '<img src="{}" style="max-height: 300px; max-width: 100%;" />',
            photo.image.url,
        )

    @admin.action(description='Hide selected photos')
    def hide_photos(self, request, queryset):
        updated = queryset.update(is_hidden=True)
        self.message_user(request, f'{updated} photo(s) hidden.')

    @admin.action(description='Unhide selected photos')
    def unhide_photos(self, request, queryset):
        updated = queryset.update(is_hidden=False)
        self.message_user(request, f'{updated} photo(s) restored.')


@admin.register(MenuItem)
class MenuItemAdmin(admin.ModelAdmin):
    list_display = ['name', 'establishment', 'category', 'price', 'is_available']
    list_filter = ['category', 'is_available', 'establishment']
    search_fields = ['name', 'description']
    list_editable = ['is_available']


@admin.register(Space)
class SpaceAdmin(admin.ModelAdmin):
    list_display = ['name', 'establishment', 'type', 'capacity']
    list_filter = ['type', 'establishment']
    search_fields = ['name', 'establishment__name']