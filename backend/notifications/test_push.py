"""Reaching a merchant's phone without them opening the app.

Slice 7 already recorded what would be sent. These cover the half that makes
it arrive: which devices a message goes to, and what happens to a token for a
handset that no longer exists.
"""

from django.contrib.auth.models import User
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from notifications.devices import DeviceToken
from notifications.push import ConsolePushSender, get_push_sender, push_to_user

SENT = []


class RecordingSender(ConsolePushSender):
    """Records instead of printing, and reports whatever is queued as dead."""

    dead = []

    def send(self, tokens, title, body, data=None):
        SENT.append({'tokens': list(tokens), 'title': title, 'body': body})
        return list(self.dead)


RECORDING = override_settings(
    PUSH_SENDER='notifications.test_push.RecordingSender'
)


@RECORDING
class PushTargetingTests(TestCase):
    def setUp(self):
        SENT.clear()
        RecordingSender.dead = []
        self.owner = User.objects.create_user('amadou', password='pw-for-tests')

    def device(self, token, user=None):
        return DeviceToken.objects.create(user=user or self.owner, token=token)

    def test_every_device_the_account_registered(self):
        """**The rule.** A venue has a tablet on the counter and a phone in
        a pocket; an alert reaching only one is worse than none, because
        whoever holds the other believes they are covered."""
        self.device('tablet-token')
        self.device('phone-token')

        reached = push_to_user(self.owner, 'New booking', '19:30, 4 people')

        self.assertEqual(reached, 2)
        self.assertCountEqual(
            SENT[0]['tokens'], ['tablet-token', 'phone-token']
        )

    def test_somebody_else_devices_are_not_touched(self):
        other = User.objects.create_user('fatou', password='pw-for-tests')
        self.device('mine')
        self.device('theirs', user=other)

        push_to_user(self.owner, 'New booking', 'x')

        self.assertEqual(SENT[0]['tokens'], ['mine'])

    def test_an_account_with_no_devices_sends_nothing(self):
        self.assertEqual(push_to_user(self.owner, 'x', 'y'), 0)
        self.assertEqual(SENT, [])

    def test_a_dead_token_is_deleted_rather_than_retried_forever(self):
        """A wiped handset otherwise stays in the table and every future
        alert pays to send to it."""
        self.device('live')
        self.device('wiped')
        RecordingSender.dead = ['wiped']

        reached = push_to_user(self.owner, 'x', 'y')

        self.assertEqual(reached, 1)
        self.assertFalse(DeviceToken.objects.filter(token='wiped').exists())
        self.assertTrue(DeviceToken.objects.filter(token='live').exists())


class SenderChoiceTests(TestCase):
    def test_the_console_sender_is_what_runs_by_default(self):
        """Not a placeholder: because it runs everywhere, the code path
        around it is exercised on every test rather than on the day
        credentials appear."""
        self.assertIsInstance(get_push_sender(), ConsolePushSender)

    @RECORDING
    def test_and_it_is_swapped_by_configuration_alone(self):
        self.assertIsInstance(get_push_sender(), RecordingSender)


class RegistrationTests(APITestCase):
    def setUp(self):
        self.owner = User.objects.create_user('amadou', password='pw-for-tests')
        self.authenticate(self.owner)

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def register(self, token='handset-1', **extra):
        return self.client.post(
            reverse('device-registration'),
            {'token': token, **extra},
            format='json',
        )

    def test_a_device_can_be_claimed(self):
        response = self.register()

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertTrue(DeviceToken.objects.filter(token='handset-1').exists())

    def test_registering_twice_does_not_make_two(self):
        """The app registers at every launch, because Firebase reissues
        tokens and a registration done once at sign-in quietly stopped being
        true months ago."""
        self.register()
        self.register()

        self.assertEqual(DeviceToken.objects.count(), 1)

    def test_a_shared_tablet_moves_rather_than_alerting_both(self):
        """**The one that would leak a venue's bookings.** Sign out, sign in
        as somebody else, and the handset must stop hearing from the first
        account."""
        self.register('counter-tablet')
        fatou = User.objects.create_user('fatou', password='pw-for-tests')
        self.authenticate(fatou)

        self.register('counter-tablet')

        device = DeviceToken.objects.get(token='counter-tablet')
        self.assertEqual(device.user, fatou)
        self.assertEqual(DeviceToken.objects.count(), 1)

    def test_signing_out_gives_the_device_up(self):
        self.register()

        response = self.client.delete(
            reverse('device-registration'),
            {'token': 'handset-1'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(DeviceToken.objects.exists())

    def test_giving_up_a_device_never_registered_is_fine(self):
        response = self.client.delete(
            reverse('device-registration'),
            {'token': 'never-seen'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

    def test_a_signed_out_caller_cannot_register_anything(self):
        self.client.credentials()

        self.assertEqual(
            self.register().status_code, status.HTTP_401_UNAUTHORIZED
        )
