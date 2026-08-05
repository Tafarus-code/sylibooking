"""Token login for the merchant app.

The Flutter app cannot use session cookies comfortably, so it exchanges a
username and password for a token once and sends it as
``Authorization: Token <key>`` thereafter.
"""

from django.contrib.auth import get_user_model
from rest_framework import serializers, status
from rest_framework.authtoken.models import Token
from rest_framework.authtoken.serializers import AuthTokenSerializer
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from establishments.models import Establishment

from .throttling import LoginIpThrottle, LoginUsernameThrottle

User = get_user_model()


class MerchantEstablishmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Establishment
        fields = ['id', 'name', 'city', 'type']


class MerchantUserSerializer(serializers.ModelSerializer):
    """Who is logged in, and which establishments they may manage."""

    establishments = MerchantEstablishmentSerializer(many=True, read_only=True)
    is_superuser = serializers.BooleanField(read_only=True)

    class Meta:
        model = User
        fields = [
            'id',
            'username',
            'first_name',
            'last_name',
            'establishments',
            'is_superuser',
        ]


class LoginView(APIView):
    """POST username + password, get back a token and the user's venues."""

    authentication_classes = []
    permission_classes = []
    # Per connection and per account. An attacker rotating IPs still has to
    # name the account; a staff room sharing one connection should not lock
    # each other out.
    throttle_classes = [LoginIpThrottle, LoginUsernameThrottle]

    def post(self, request):
        serializer = AuthTokenSerializer(
            data=request.data, context={'request': request}
        )
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']
        token, _ = Token.objects.get_or_create(user=user)
        return Response(
            {'token': token.key, 'user': MerchantUserSerializer(user).data}
        )


class LogoutView(APIView):
    """Discard the caller's token, so a lost phone can be cut off."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        Token.objects.filter(user=request.user).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(APIView):
    """Used on app start to check a stored token is still good."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(MerchantUserSerializer(request.user).data)