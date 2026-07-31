"""Who may take orders.

Deliberately a validation rule and not a database constraint. Restricting
ordering to restaurants is a product decision made this month, not a truth
about the data — lounges serving food to collect is an obvious next step, and
when it comes this is the one line that changes rather than a migration.
"""

from establishments.models import Establishment


def can_take_orders(establishment):
    """True when this establishment is allowed to accept pickup orders."""
    return establishment.type == Establishment.Type.RESTAURANT


def order_refusal_reason(establishment):
    """Why this establishment cannot take orders, or None if it can."""
    if can_take_orders(establishment):
        return None
    return (
        f'{establishment.name} is a '
        f'{establishment.get_type_display().lower()}, and only restaurants '
        f'take orders ahead. You can still book a table.'
    )
