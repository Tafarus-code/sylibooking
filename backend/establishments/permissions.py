"""Who may do what at an establishment.

One place, so a new endpoint cannot quietly invent its own rules. Every check
is a database lookup against MerchantMembership rather than anything cached on
the token, which is what makes a role change take effect on the caller's very
next request instead of at their next login.
"""

from django.utils.translation import gettext as _
from rest_framework.exceptions import NotFound, PermissionDenied

from .models import Establishment, MerchantMembership


def membership_for(user, establishment):
    """The user's membership at this establishment, or None.

    A superuser has no row but is treated as an owner everywhere, matching how
    the rest of the API already handles them.
    """
    if user is None or not user.is_authenticated:
        return None

    if user.is_superuser:
        return MerchantMembership(
            user=user,
            establishment=establishment,
            role=MerchantMembership.Role.OWNER,
        )

    return MerchantMembership.objects.filter(
        user=user, establishment=establishment
    ).first()


def get_establishment_or_404(establishment_id):
    establishment = Establishment.objects.filter(pk=establishment_id).first()
    if establishment is None:
        raise NotFound(_('No such establishment.'))
    return establishment


def require_membership(user, establishment, allowed_roles=None, action=None):
    """Return the caller's membership, or refuse.

    A non-member gets 404 rather than 403: confirming that an establishment
    exists and that they simply lack rights tells an outsider more than they
    need. A member whose role is too low gets 403 and a reason, because they
    are entitled to know why.
    """
    membership = membership_for(user, establishment)
    if membership is None:
        raise NotFound(_('No such establishment.'))

    if allowed_roles is not None and membership.role not in allowed_roles:
        raise PermissionDenied(
            f'Your role here is {membership.get_role_display().lower()}. '
            f'{action or "That"} is not something you can do.'
        )

    return membership


def require_profile_access(user, establishment):
    """Editing the venue itself: hours, menu, photos, description."""
    return require_membership(
        user,
        establishment,
        allowed_roles=MerchantMembership.PROFILE_ROLES,
        action='Editing the venue profile',
    )


def require_staff_management(user, establishment):
    """Adding, removing or re-roling members. Owner alone."""
    return require_membership(
        user,
        establishment,
        allowed_roles=MerchantMembership.MEMBERSHIP_ROLES,
        action='Managing who has access',
    )


def require_operations_access(user, establishment):
    """Running the floor. Any member, whatever their role."""
    return require_membership(
        user,
        establishment,
        allowed_roles=MerchantMembership.OPERATIONS_ROLES,
        action='Working this venue',
    )


def memberships_of(user):
    """Every membership the user holds, venues prefetched."""
    if user is None or not user.is_authenticated:
        return MerchantMembership.objects.none()
    return MerchantMembership.objects.filter(user=user).select_related(
        'establishment'
    )


def establishments_for(user):
    """Establishments the user may operate.

    Superusers see everything, as they do elsewhere in the API.
    """
    if user is None or not user.is_authenticated:
        return Establishment.objects.none()
    if user.is_superuser:
        return Establishment.objects.all()
    return Establishment.objects.filter(memberships__user=user)
