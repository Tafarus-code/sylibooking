"""Registering the phone an alert should reach.

Called at every launch rather than once at sign-in. Firebase reissues tokens
— on reinstall, on restore to a new handset, and sometimes for its own
reasons — and a registration that happened once at sign-in is a registration
that quietly stopped being true months ago.
"""

from notifications.devices import DeviceToken
from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView


class DeviceTokenSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=255)
    platform = serializers.ChoiceField(
        choices=DeviceToken.Platform.choices,
        default=DeviceToken.Platform.ANDROID,
    )


class DeviceRegistrationView(APIView):
    """POST to claim a device for this account, DELETE to give it up."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        form = DeviceTokenSerializer(data=request.data)
        form.is_valid(raise_exception=True)

        # update_or_create on the token, not on (user, token): a shared
        # tablet signed out of one account and into another must move, not
        # end up alerting both. The token identifies the handset; whoever is
        # signed in on it now is who should hear from it.
        DeviceToken.objects.update_or_create(
            token=form.validated_data['token'],
            defaults={
                'user': request.user,
                'platform': form.validated_data['platform'],
            },
        )
        return Response(status=status.HTTP_204_NO_CONTENT)

    def delete(self, request):
        """Signing out on this handset. Idempotent — a device that was never
        registered is already in the state being asked for."""
        token = request.data.get('token') or ''
        DeviceToken.objects.filter(token=token, user=request.user).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
