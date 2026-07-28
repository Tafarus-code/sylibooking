from django.contrib import admin

from .models import Payment


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'reservation',
        'provider',
        'amount',
        'status',
        'provider_reference',
        'created_at',
    ]
    list_filter = ['status', 'provider', 'created_at']
    search_fields = [
        'provider_reference',
        'reservation__customer_name',
        'reservation__reference',
    ]
    list_select_related = ['reservation']
    # Status and reference come from the provider; editing them by hand would
    # let the admin claim money that was never taken.
    readonly_fields = ['provider_reference', 'status', 'created_at']
