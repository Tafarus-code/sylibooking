"""How long a table is held for someone who has not turned up.

One number cannot serve both kinds of venue. A lounge table is not lost at
minute 16 — its turnover pressure comes late, and guests arriving an hour
after their time is ordinary. A restaurant table held ninety minutes through a
dinner service costs more in refused walk-ins than the deposit protects, so
the grace period would be losing the venue money to guard a smaller sum.

The window a booking is judged against is captured on the booking itself when
it is taken, never read live from here. A customer is told the grace period
when they book; shortening a venue's window afterwards must not retroactively
turn an existing booking into a forfeited deposit. This module answers "what
window would a booking taken *now* get", and nothing else.
"""

from django.conf import settings


def no_show_window(establishment):
    """Minutes after its time before a booking here counts as a no-show.

    Per establishment type today. A per-venue override column lands later and
    lands here, so every caller picks it up at once — which is the reason this
    is a function rather than a dictionary lookup at each call site.
    """
    windows = settings.NO_SHOW_WINDOW_MINUTES
    return windows.get(establishment.type, windows['restaurant'])
