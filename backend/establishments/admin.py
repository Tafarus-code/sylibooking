from django.contrib import admin

from .models import Establishment, MenuItem, OpeningHours, Space


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