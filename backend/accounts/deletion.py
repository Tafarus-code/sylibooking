"""Closing a customer account without erasing a venue's books.

Two things are true at once and pull in opposite directions. A customer who
asks to be forgotten should be forgotten. And a merchant's takings for last
March are the merchant's record, not the customer's — deleting a booking
because the person who made it closed their account would quietly rewrite
somebody else's revenue.

So the row survives and the person does not. A past booking keeps its date,
its table, its party size and its money; it loses the name and the number
that said whose it was. What is left is a sitting that happened, which is
what the venue is entitled to remember.

What goes entirely is anything that is only about the person: their profile,
their saved venues, any outstanding reset codes, their sign-in token. None of
that is a record of anything a venue did.

Reviews stay, and stay attached to their booking. A rating that vanished when
its author closed their account would let anybody launder a venue's score by
signing up, reviewing, and leaving. The name on it is already only a first
name, and once the booking is scrubbed it falls back to "Guest".
"""

from django.db import transaction
from django.utils.translation import gettext_lazy as _
from orders.models import Order

from reservations.models import Reservation


def close_account(user):
    """Scrub the person, keep the history. Returns a summary of what changed.

    Deliberately not a signal on `post_delete`: this is a decision with
    consequences for somebody else's books, and it should be readable in one
    place rather than inferred from a receiver somewhere.
    """
    with transaction.atomic():
        bookings = Reservation.objects.filter(customer=user)
        orders = Order.objects.filter(customer=user)

        # Blank rather than a marker like "Deleted account": the review's
        # author name is derived from this field, and a marker would put the
        # word "Deleted" under somebody's rating. Empty falls back to "Guest"
        # there, and the apps show their own wording on a merchant's list.
        scrubbed_bookings = bookings.update(customer_name='', customer_phone='')
        scrubbed_orders = orders.update(customer_name='', customer_phone='')

        # Everything hanging off the user that is only about the user goes
        # with it: profile, favourites, reset codes and token all cascade.
        user.delete()

    return {
        'reservations': scrubbed_bookings,
        'orders': scrubbed_orders,
    }


def refusal_reason(user):
    """Why this account cannot be closed here, or None.

    A merchant account is not a customer account that happens to work at a
    venue: closing it would take somebody's staff access with it, and the
    person who should decide that is the venue's owner.
    """
    if user.merchant_memberships.exists():
        return _(
            'This account also works at a venue. Ask an owner to remove your '
            'access there first.'
        )
    if user.is_staff or user.is_superuser:
        return _('Administrator accounts are closed by an administrator.')
    return None
