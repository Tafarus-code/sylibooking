"""Ceilings on the endpoints anyone can reach without signing in.

Until a real payment gateway is attached, the worst an abuser gets from
hammering these is junk rows. That changes the moment one is: mobile money
initiation pushes a prompt to whatever phone number the caller typed, so an
unthrottled booking-create becomes a way to fire payment prompts at any
number in Guinea, as often as they like, from our provider account. That is a
harassment vector wearing our name, and it is the reason this lands before
the gateway rather than after.

Two keys, not one. An IP alone is useless against somebody rotating IPs, and
useless *to* somebody sharing one — a whole venue behind one connection is
not one abuser. So the paths that matter are limited by IP *and* by the thing
being targeted: the username being guessed, the phone number being spammed.

Throttling is off during tests. Turning it on for the suite would mean every
test that signs in twice fighting a counter that outlives it, and the tests
that actually care switch it back on explicitly.
"""

from django.conf import settings
from rest_framework.settings import api_settings
from rest_framework.throttling import (
    AnonRateThrottle,
    SimpleRateThrottle,
    UserRateThrottle,
)


class _Switchable:
    """Lets a throttle be turned off wholesale, and read its rate live.

    DRF treats a rate of None as "no limit", which is exactly the behaviour
    wanted when the switch is off. A mixin rather than a base class so it can
    sit in front of DRF's own anon and user throttles too.

    The rate is looked up through `api_settings` on every instance rather
    than through the dict DRF binds to the class at import. They are normally
    the same dict; they stop being the same the moment a test overrides the
    rates, and a throttle that quietly kept serving the rates the process
    started with would make every one of those tests pass by accident.
    """

    def get_rate(self):
        if not getattr(settings, 'THROTTLING_ENABLED', True):
            return None
        rates = api_settings.DEFAULT_THROTTLE_RATES
        if self.scope in rates:
            return rates[self.scope]
        return super().get_rate()


class _SwitchableThrottle(_Switchable, SimpleRateThrottle):
    pass


class _IdentifiedThrottle(_SwitchableThrottle):
    """Keyed on something in the request body rather than on the caller.

    Subclasses say which field. A request that does not carry it is not
    throttled by this class at all — the companion IP throttle still applies,
    and refusing a request for lacking the field a *validator* is about to
    reject would give a worse error message.
    """

    field = None

    def get_cache_key(self, request, view):
        value = self._value(request)
        if not value:
            return None
        return self.cache_format % {
            'scope': self.scope,
            'ident': value.strip().lower(),
        }

    def _value(self, request):
        data = getattr(request, 'data', None)
        if not isinstance(data, dict):
            return None
        return data.get(self.field)


class LoginIpThrottle(_SwitchableThrottle):
    """Signing in, per connection."""

    scope = 'login_ip'

    def get_cache_key(self, request, view):
        return self.cache_format % {
            'scope': self.scope,
            'ident': self.get_ident(request),
        }


class LoginUsernameThrottle(_IdentifiedThrottle):
    """Signing in, per account being guessed at.

    Separate from the IP limit on purpose: an attacker rotating IPs still has
    to name the account, and a staff room sharing one connection should not
    lock each other out.
    """

    scope = 'login_username'
    field = 'username'


class RegistrationThrottle(_SwitchableThrottle):
    scope = 'register'

    def get_cache_key(self, request, view):
        return self.cache_format % {
            'scope': self.scope,
            'ident': self.get_ident(request),
        }


class PasswordResetIpThrottle(_SwitchableThrottle):
    scope = 'password_reset'

    def get_cache_key(self, request, view):
        return self.cache_format % {
            'scope': self.scope,
            'ident': self.get_ident(request),
        }


class PasswordResetIdentifierThrottle(_IdentifiedThrottle):
    """**The hole this slice exists to close.**

    The five-attempt cap on a reset code is *per code*. Nothing caps how many
    codes may be requested, so unthrottled it is unlimited attempts wearing a
    fresh code each time — and once SMS actually leaves the machine, unlimited
    messages billed to us and sent at somebody who never asked.
    """

    scope = 'password_reset_identifier'
    field = 'identifier'


class BookingIpThrottle(_SwitchableThrottle):
    """Creating a booking, per connection.

    Deliberately generous: a shared connection at an office or a cybercafé is
    a normal way for several real customers to book.
    """

    scope = 'booking_ip'

    def get_cache_key(self, request, view):
        return self.cache_format % {
            'scope': self.scope,
            'ident': self.get_ident(request),
        }


class BookingPhoneThrottle(_IdentifiedThrottle):
    """Creating a booking, per phone number named.

    The one that actually blunts prompt-spam: an abuser rotating IPs still
    has to pick a victim's number, and this caps how often that number can be
    made to ring.
    """

    scope = 'booking_phone'
    field = 'customer_phone'


class AnonSurfaceThrottle(_Switchable, AnonRateThrottle):
    """The floor under everything nobody has signed in to reach.

    Applied as a project default so a route added next month is covered by
    having been written, not by somebody remembering to cover it. Every named
    throttle above is tighter and set per view; DRF replaces the defaults
    where a view names its own, which is the intended order — the specific
    limit wins on the paths that earned one, and this catches the rest.

    Deliberately loose. A blanket rate wants real traffic to size, and there
    is none yet: guessing low would throttle the first pilot for nothing.
    Sizing this properly is Slice 20 work, once throttle hits are visible.
    """

    scope = 'anon_surface'


class UserSurfaceThrottle(_Switchable, UserRateThrottle):
    """The same floor for signed-in callers, keyed on the account.

    Higher than the anonymous one on purpose: a merchant tablet on the floor
    polls for new bookings all evening, and that is the app working, not an
    abuser. Somebody who is signed in is also somebody who can be identified
    and turned off, which the anonymous surface cannot offer.
    """

    scope = 'user_surface'


class BrowseThrottle(_SwitchableThrottle):
    """The public catalogue, per connection.

    The venue list, the search and the availability lookups are open to
    anyone, which is the point — but they are also the whole product's data,
    and nothing currently stops a competitor pulling all of it nightly. This
    is a nuisance ceiling rather than a defence: it does not stop somebody
    determined and patient, it stops the cheap version.

    Keyed on IP for everyone, signed in or not, because it is the pull that
    costs, not who is doing it.
    """

    scope = 'browse'

    def get_cache_key(self, request, view):
        return self.cache_format % {
            'scope': self.scope,
            'ident': self.get_ident(request),
        }
