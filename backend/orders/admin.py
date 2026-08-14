from django.contrib import admin

from .models import Order, OrderItem


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    extra = 0
    # The snapshot is the record of what was charged. Editing it here would
    # rewrite history, which is the one thing it exists to prevent.
    readonly_fields = ['menu_item', 'quantity', 'unit_price_at_order']
    can_delete = False


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'customer_name',
        'establishment',
        'pickup_time',
        'status',
        'total',
    ]
    list_filter = ['status', 'establishment', 'pickup_time']
    search_fields = ['customer_name', 'customer_phone', 'reference']
    date_hierarchy = 'pickup_time'
    readonly_fields = ['reference', 'created_at', 'total']
    inlines = [OrderItemInline]

    def get_queryset(self, request):
        return (
            super()
            .get_queryset(request)
            .select_related('establishment', 'reservation')
            .prefetch_related('items')
        )
