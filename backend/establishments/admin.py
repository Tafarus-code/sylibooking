from django.contrib import admin

from .models import Establishment, Space


class SpaceInline(admin.TabularInline):
    """Add tables/rooms while creating the establishment, in one screen."""

    model = Space
    extra = 3


@admin.register(Establishment)
class EstablishmentAdmin(admin.ModelAdmin):
    list_display = ['name', 'type', 'city', 'created_at']
    list_filter = ['type', 'city']
    search_fields = ['name', 'address']
    inlines = [SpaceInline]


@admin.register(Space)
class SpaceAdmin(admin.ModelAdmin):
    list_display = ['name', 'establishment', 'type', 'capacity']
    list_filter = ['type', 'establishment']
    search_fields = ['name', 'establishment__name']