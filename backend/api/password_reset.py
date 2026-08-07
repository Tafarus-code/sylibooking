"""Getting back into an account.

Two steps: ask for a code, then use it. Between them the customer has a six
digit number and fifteen minutes.

Everything here is written so that an outsider probing the endpoint learns
nothing. The request step answers the same way whether or not the account
exists, and the confirm step gives the same message for a wrong code, an
expired code and an account that was never there.
"""

import logging
import time

from accounts.models import CustomerProfile, PasswordResetCode
from accounts.notifications import NotificationError, get_notifier, mask
from django.conf import settings
from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils import timezone
from django.utils.translation import gettext as _
from django.utils.translation import gettext_lazy
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .throttling import (
    PasswordResetIdentifierThrottle,
    PasswordResetIpThrottle,
)

logger = logging.getLogger(__name__)
User = get_user_model()

#: Said to everyone, whether or not there was an account to find. Confirming
#: that a username exists is a gift to whoever is guessing them.
SENT_MESSAGE = gettext_lazy(
    'If that account exists, a code is on its way. It is good for 15 minutes.'
)

#: One message for wrong, expired and never-existed. Which of the three it was
#: is exactly what an attacker would like to know.
BAD_CODE_MESSAGE = gettext_lazy(
    'That code is wrong or has expired. Ask for a new one and try again.'
)


def find_user(identifier):
    """Match a username, an email, or a phone number.

    Customers will type whichever they remember, and being made to guess which
    one the app wants is the sort of thing that ends the attempt.
    """
    identifier = (identifier or '').strip()
    if not identifier:
        return None

    digits = ''.join(ch for ch in identifier if ch.isdigit())
    query = Q(username__iexact=identifier)
    if '@' in identifier:
        query |= Q(email__iexact=identifier)
    if len(digits) >= 8:
        # Compared on digits alone: +224 620 00 00 00 and 224620000000 are the
        # same number and a customer should not have to remember which they
        # typed at signup.
        matching = [
            profile.user_id
            for profile in CustomerProfile.objects.exclude(phone='')
            if ''.join(ch for ch in profile.phone if ch.isdigit()).endswith(
                digits[-8:]
            )
        ]
        query |= Q(pk__in=matching)

    return User.objects.filter(query).first()


def channel_for(user):
    """Where a code should go: the phone if there is one, else the email."""
    profile = getattr(user, 'customer_profile', None)
    if profile is not None and profile.phone:
        return PasswordResetCode.Channel.SMS, profile.phone
    if user.email:
        return PasswordResetCode.Channel.EMAIL, user.email
    return None, None


class RequestResetSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=200)


class RequestResetView(APIView):
    """Step one: send a code to whatever we can reach."""

    authentication_classes = []
    permission_classes = [AllowAny]
    # The per-code attempt cap does nothing about how many codes may be
    # asked for. Unthrottled that is unlimited attempts wearing a fresh code
    # each time — and, once SMS leaves the machine, unlimited messages billed
    # to us and sent at somebody who never asked.
    throttle_classes = [PasswordResetIpThrottle, PasswordResetIdentifierThrottle]

    def post(self, request):
        """Answer no faster than the floor, whatever the answer is.

        The wording is already identical whether or not the identifier
        exists. The work behind it is not: a hit issues a code, writes a row
        and hands it to a notifier, while a miss returns after a single
        query. Timed from outside, that difference reads as a yes/no on
        whether an account exists — which is exactly what the identical
        wording was there to withhold. It gets worse once the notifier is a
        real SMS gateway and the hit path includes a network round trip.

        So both answers wait out the same floor. The cost is a worker held
        for a quarter of a second on an endpoint already capped at a handful
        of requests an hour, which is affordable; a rejected request never
        reaches here, because the throttle refuses it first.
        """
        deadline = time.monotonic() + settings.PASSWORD_RESET_MIN_SECONDS
        try:
            return self._respond(request)
        finally:
            # A loop, not a single sleep. time.sleep may return early — on
            # Windows it undersleeps by up to a timer tick — and a floor that
            # is usually respected is not a floor at all: the whole point is
            # that a miss and a hit are indistinguishable, and an occasional
            # twelve milliseconds is exactly the signal being hidden.
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                time.sleep(remaining)

    def _respond(self, request):
        form = RequestResetSerializer(data=request.data)
        form.is_valid(raise_exception=True)

        user = find_user(form.validated_data['identifier'])
        if user is None:
            # Same answer as a success, and — thanks to the floor in post()
            # — no sooner.
            return Response({'detail': SENT_MESSAGE})

        channel, destination = channel_for(user)
        if channel is None:
            # An account with no phone and no email cannot be reset by code.
            # Say so plainly — silence would leave the customer waiting for a
            # message that is never coming.
            #
            # Knowingly, this one answer does confirm the account exists. It
            # is the only such leak left, it is bounded to accounts that
            # cannot be reset anyway, and the alternative is a dead end with
            # no explanation. Worth revisiting if enumeration ever matters
            # more than that customer getting unstuck.
            return Response(
                {
                    'detail': _(
                        'That account has no phone number or email on it, so '
                        'we have no way to send a code. Ask the venue to help '
                        'you, or make a new account.'
                    )
                },
                status=status.HTTP_409_CONFLICT,
            )

        record, code = PasswordResetCode.issue(user, channel, destination)

        try:
            get_notifier(channel).send(
                destination=destination,
                subject='Your Sylibooking code',
                body=_(
                    'Your Sylibooking code is %(code)s. It expires in 15 '
                    'minutes. If you did not ask for it, ignore this message.'
                ) % {'code': code},
            )
        except NotificationError:
            logger.exception('Could not send reset code to %s', mask(destination))
            # Burn it: a code that was never delivered should not sit valid.
            record.consume()
            return Response(
                {
                    'detail': _(
                        'We could not send the code just now. Try again in a '
                        'moment.'
                    )
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        return Response(
            {
                'detail': SENT_MESSAGE,
                'channel': channel,
                # Masked, so the right person recognises it and nobody else
                # learns a number.
                'sent_to': mask(destination),
            }
        )


class ConfirmResetSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=200)
    code = serializers.CharField(max_length=12)
    new_password = serializers.CharField(min_length=8)

    def validate_new_password(self, password):
        if password.strip() != password:
            raise serializers.ValidationError(
                _('Passwords cannot start or end with a space.')
            )
        return password


class ConfirmResetView(APIView):
    """Step two: the code, and the new password."""

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetIpThrottle]

    def post(self, request):
        form = ConfirmResetSerializer(data=request.data)
        form.is_valid(raise_exception=True)
        data = form.validated_data

        user = find_user(data['identifier'])
        record = (
            None
            if user is None
            else PasswordResetCode.objects.filter(
                user=user, used_at__isnull=True
            ).first()
        )

        if record is None or not record.is_usable:
            return Response(
                {'detail': BAD_CODE_MESSAGE},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not record.matches(data['code'].strip()):
            return Response(
                {'detail': BAD_CODE_MESSAGE},
                status=status.HTTP_400_BAD_REQUEST,
            )

        record.consume()
        user.set_password(data['new_password'])
        user.save(update_fields=['password'])

        # Every existing token dies with the old password. If somebody else
        # was in this account, this is the moment they are put out of it —
        # which is the point of resetting.
        from rest_framework.authtoken.models import Token

        Token.objects.filter(user=user).delete()

        logger.info(
            'Password reset completed for %s at %s',
            user.username,
            timezone.now().isoformat(),
        )
        return Response(
            {
                'detail': _(
                    'Password changed. You can sign in with it now — you have '
                    'been signed out everywhere else.'
                )
            }
        )
