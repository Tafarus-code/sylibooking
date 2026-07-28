from django.contrib import admin

from .models import Reservation


@admin.register(Reservation)
class ReservationAdmin(admin.ModelAdmin):
    list_display = [
        'customer_name',
        'space',
        'datetime',
        'party_size',
        'status',
        'created_at',
    ]
    list_filter = ['status', 'space__establishment', 'datetime']
    search_fields = ['customer_name', 'customer_phone', 'reference']
    readonly_fields = ['reference', 'created_at']
    list_select_related = ['space', 'space__establishment']
    date_hierarchy = 'datetime'