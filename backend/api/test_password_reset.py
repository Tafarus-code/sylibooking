"""Getting back into an account.

Two things are being protected here at once: a customer who genuinely forgot
their password, and every account from whoever is probing the endpoint. Most
of these tests are about the second.
"""

from datetime import timedelta

from accounts.models import CustomerProfile, PasswordResetCode
from accounts.notifications import mask
from django.contrib.auth import get_user_model
from django.core import mail
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

User = get_user_model()

#: Captures what would have been sent, so a test can read the code.
CAPTURED = []


class CapturingNotifier:
    def send(self, destination, subject, body):
        CAPTURED.append({'to': destination, 'body': body})


class FailingNotifier:
    def send(self, destination, subject, body):
        from accounts.notifications import NotificationError

        raise NotificationError('gateway down')


CAPTURING = {
    'sms': f'{__name__}.CapturingNotifier',
    'email': f'{__name__}.CapturingNotifier',
}
FAILING = {
    'sms': f'{__name__}.FailingNotifier',
    'email': f'{__name__}.FailingNotifier',
}


@override_settings(NOTIFIERS=CAPTURING)
class PasswordResetTests(APITestCase):
    def setUp(self):
        CAPTURED.clear()
        self.user = User.objects.create_user(
            'mariama', password='old-password-1', email='mariama@example.gn'
        )
        CustomerProfile.objects.create(
            user=self.user, phone='+224 620 00 11 22'
        )

    def request_code(self, identifier='mariama'):
        return self.client.post(
            reverse('customer-password-reset'),
            {'identifier': identifier},
            format='json',
        )

    def sent_code(self):
        """The digits out of whatever the notifier was handed."""
        body = CAPTURED[-1]['body']
        return ''.join(ch for ch in body if ch.isdigit())[:6]

    def confirm(self, code, password='brand-new-password', identifier='mariama'):
        return self.client.post(
            reverse('customer-password-reset-confirm'),
            {
                'identifier': identifier,
                'code': code,
                'new_password': password,
            },
            format='json',
        )


class RequestingACodeTests(PasswordResetTests):
    def test_a_code_is_sent_to_the_phone_when_there_is_one(self):
        response = self.request_code()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['channel'], 'sms')
        self.assertEqual(CAPTURED[-1]['to'], '+224 620 00 11 22')

    def test_email_is_the_fallback(self):
        self.user.customer_profile.phone = ''
        self.user.customer_profile.save()

        response = self.request_code()

        self.assertEqual(response.data['channel'], 'email')

    def test_the_destination_comes_back_masked(self):
        response = self.request_code()

        # Enough to recognise, not enough to use.
        self.assertNotIn('620001122', response.data['sent_to'])
        self.assertIn('…', response.data['sent_to'])

    def test_an_unknown_account_gets_the_same_answer(self):
        response = self.request_code('nobody-at-all')

        # Saying "no such user" hands an attacker a list of valid names.
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('If that account exists', response.data['detail'])
        self.assertEqual(CAPTURED, [])

    def test_the_phone_number_can_be_used_to_ask(self):
        response = self.request_code('620001122')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(CAPTURED), 1)

    def test_the_email_can_be_used_to_ask(self):
        response = self.request_code('mariama@example.gn')

        self.assertEqual(len(CAPTURED), 1)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_an_account_with_no_contact_is_told_plainly(self):
        alone = User.objects.create_user('alone', password='x' * 10)
        CustomerProfile.objects.create(user=alone, phone='')

        response = self.request_code('alone')

        # Not a secret, and silence would leave them waiting forever.
        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('no way to send', response.data['detail'])

    def test_the_code_is_never_stored_in_the_clear(self):
        self.request_code()
        code = self.sent_code()

        record = PasswordResetCode.objects.get()
        self.assertNotEqual(record.code_hash, code)
        self.assertEqual(record.code_hash, PasswordResetCode.hash_code(code))

    def test_asking_again_kills_the_first_code(self):
        self.request_code()
        first = self.sent_code()
        self.request_code()

        response = self.confirm(first)

        # A code read over a shoulder must not outlive the request that
        # replaced it.
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    @override_settings(NOTIFIERS=FAILING)
    def test_a_gateway_failure_is_reported_and_the_code_burned(self):
        response = self.request_code()

        self.assertEqual(
            response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE
        )
        record = PasswordResetCode.objects.get()
        self.assertIsNotNone(record.used_at)


class UsingACodeTests(PasswordResetTests):
    def test_the_right_code_changes_the_password(self):
        self.request_code()

        response = self.confirm(self.sent_code())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('brand-new-password'))

    def test_the_new_password_works_at_the_login_endpoint(self):
        self.request_code()
        self.confirm(self.sent_code())

        response = self.client.post(
            reverse('auth-login'),
            {'username': 'mariama', 'password': 'brand-new-password'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_a_wrong_code_is_refused(self):
        self.request_code()

        response = self.confirm('000000' if self.sent_code() != '000000' else '111111')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('old-password-1'))

    def test_wrong_and_expired_read_the_same(self):
        self.request_code()
        wrong = self.confirm('000000' if self.sent_code() != '000000' else '111111')

        PasswordResetCode.objects.update(
            expires_at=timezone.now() - timedelta(minutes=1)
        )
        expired = self.confirm(self.sent_code())

        # Which of the two it was is what an attacker would like to know.
        self.assertEqual(wrong.data['detail'], expired.data['detail'])

    def test_a_code_works_once(self):
        self.request_code()
        code = self.sent_code()
        self.confirm(code)

        response = self.confirm(code, password='another-password-2')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_expired_code_is_refused(self):
        self.request_code()
        PasswordResetCode.objects.update(
            expires_at=timezone.now() - timedelta(seconds=1)
        )

        response = self.confirm(self.sent_code())

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_guessing_is_capped(self):
        self.request_code()
        real = self.sent_code()
        wrong = '000000' if real != '000000' else '111111'

        for _ in range(PasswordResetCode.MAX_ATTEMPTS):
            self.confirm(wrong)

        # Even the right code is refused once the budget is spent.
        response = self.confirm(real)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('old-password-1'))

    def test_resetting_signs_out_every_other_device(self):
        Token.objects.create(user=self.user)
        self.request_code()

        self.confirm(self.sent_code())

        # Whoever else was in the account is put out of it, which is the point.
        self.assertFalse(Token.objects.filter(user=self.user).exists())

    def test_a_short_new_password_is_refused(self):
        self.request_code()

        response = self.confirm(self.sent_code(), password='short')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_unknown_account_reads_like_a_wrong_code(self):
        response = self.confirm('123456', identifier='nobody-at-all')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('wrong or has expired', response.data['detail'])


class RegistrationContactTests(APITestCase):
    def test_signing_up_can_record_a_phone(self):
        response = self.client.post(
            reverse('customer-register'),
            {
                'username': 'ibrahima',
                'password': 'chicha-2026',
                'name': 'Ibrahima',
                'phone': '+224620999888',
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['user']['can_reset_password'])

    def test_an_account_with_no_contact_says_it_cannot_be_reset(self):
        response = self.client.post(
            reverse('customer-register'),
            {'username': 'sekou', 'password': 'chicha-2026', 'name': 'Sékou'},
            format='json',
        )

        # The app uses this to warn them while there is still time to fix it.
        self.assertFalse(response.data['user']['can_reset_password'])


class MaskTests(APITestCase):
    def test_a_phone_keeps_its_first_four_and_last_two(self):
        self.assertEqual(mask('+224 620 00 11 22'), '2246…22')

    def test_an_email_keeps_its_domain(self):
        self.assertEqual(mask('mariama@example.gn'), 'ma…@example.gn')

    def test_something_too_short_gives_nothing_away(self):
        self.assertEqual(mask('12'), '…')


@override_settings(
    NOTIFIERS={'email': 'accounts.notifications.EmailNotifier'},
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
)
class EmailDeliveryTests(APITestCase):
    def test_the_email_notifier_actually_sends(self):
        user = User.objects.create_user(
            'aissatou', password='x' * 10, email='aissatou@example.gn'
        )
        CustomerProfile.objects.create(user=user, phone='')

        response = self.client.post(
            reverse('customer-password-reset'),
            {'identifier': 'aissatou'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn('Sylibooking', mail.outbox[0].subject)
