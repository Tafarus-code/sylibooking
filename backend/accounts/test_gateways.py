"""The SMS gateway and WhatsApp, against recorded answers.

The SMS notifier is configurable enough to be wrong in interesting ways, so
most of these are about the configuration rather than the HTTP: a payload
template that does not get filled in, a number that reaches the vendor in the
wrong shape, or a gateway that answers 200 and means no.
"""

from django.test import TestCase, override_settings

from payments.test_real_providers import FakeResponse, FakeSession

from .gateways import HttpSmsNotifier, WhatsAppNotifier, _e164
from .notifications import NotificationError

GATEWAY = {
    'url': 'https://sms.test/send',
    'method': 'POST',
    'encoding': 'json',
    'sender': 'Sylibooking',
    'username': 'user',
    'password': 'pass',
    'default_country_code': '224',
    'headers': {'X-Api-Key': 'k'},
    'payload': {'to': '{to}', 'from': '{sender}', 'text': '{text}'},
    'success_path': '',
    'success_value': '',
}

WHATSAPP = {
    'base_url': 'https://graph.test/v21.0',
    'phone_number_id': '123',
    'token': 'tok',
    'template': 'booking_reminder',
    'language': 'fr',
    'default_country_code': '224',
}


@override_settings(SMS_GATEWAY=GATEWAY)
class SmsGatewayTests(TestCase):
    def test_the_payload_template_is_filled_in(self):
        session = FakeSession(FakeResponse(200, {'ok': True}))

        HttpSmsNotifier(session=session).send(
            '+224620000001', 'Rappel', 'Votre table vous attend a 20h'
        )

        body = session.calls[0]['json']
        self.assertEqual(body['to'], '224620000001')
        self.assertEqual(body['from'], 'Sylibooking')
        self.assertEqual(body['text'], 'Votre table vous attend a 20h')

    def test_headers_and_basic_auth_are_sent(self):
        session = FakeSession(FakeResponse(200, {'ok': True}))

        HttpSmsNotifier(session=session).send('620000001', '', 'hi')

        self.assertEqual(session.calls[0]['headers']['X-Api-Key'], 'k')
        self.assertEqual(session.calls[0]['auth'], ('user', 'pass'))

    def test_form_encoding_is_available_for_older_gateways(self):
        session = FakeSession(FakeResponse(200, {'ok': True}))

        with override_settings(SMS_GATEWAY={**GATEWAY, 'encoding': 'form'}):
            HttpSmsNotifier(session=session).send('620000001', '', 'hi')

        self.assertIn('data', session.calls[0])
        self.assertNotIn('json', session.calls[0])

    def test_an_unconfigured_gateway_refuses_rather_than_posting_nowhere(self):
        with override_settings(SMS_GATEWAY={**GATEWAY, 'url': ''}):
            with self.assertRaises(NotificationError):
                HttpSmsNotifier(session=FakeSession()).send('620000001', '', 'x')

    def test_a_refusal_becomes_a_notification_error(self):
        session = FakeSession(FakeResponse(402, text='no credit'))

        with self.assertRaises(NotificationError):
            HttpSmsNotifier(session=session).send('620000001', '', 'x')

    def test_a_gateway_that_says_no_inside_a_200_is_believed(self):
        """**The failure mode generic adapters miss.**

        Plenty of aggregators answer 200 with `{"status": "FAILED"}`. Without
        the success path configured that reads as delivered, and a reminder
        nobody received is the one failure this product cannot see.
        """
        session = FakeSession(FakeResponse(200, {'status': 'FAILED'}))

        with override_settings(
            SMS_GATEWAY={
                **GATEWAY,
                'success_path': 'status',
                'success_value': 'OK',
            }
        ):
            with self.assertRaises(NotificationError):
                HttpSmsNotifier(session=session).send('620000001', '', 'x')

    def test_an_sms_is_never_retried(self):
        """A retry is a second message and a second charge."""
        import requests

        session = FakeSession(requests.ConnectionError('down'))

        with self.assertRaises(NotificationError):
            HttpSmsNotifier(session=session).send('620000001', '', 'x')

        self.assertEqual(len(session.calls), 1)


class NumberShapeTests(TestCase):
    def test_a_local_number_gains_the_country_code(self):
        self.assertEqual(_e164('620 00 00 01', '224'), '224620000001')

    def test_a_leading_zero_is_dropped(self):
        self.assertEqual(_e164('0620000001', '224'), '224620000001')

    def test_a_full_number_is_left_alone(self):
        self.assertEqual(_e164('+224 620 00 00 01', '224'), '224620000001')

    def test_nothing_in_is_nothing_out(self):
        self.assertEqual(_e164('', '224'), '')
        self.assertEqual(_e164(None, '224'), '')


@override_settings(WHATSAPP=WHATSAPP)
class WhatsAppTests(TestCase):
    def test_it_sends_the_configured_template(self):
        session = FakeSession(FakeResponse(200, {'messages': [{'id': 'x'}]}))

        WhatsAppNotifier(session=session).send(
            '620000001', '', 'Votre table vous attend a 20h'
        )

        body = session.calls[0]['json']
        self.assertEqual(body['messaging_product'], 'whatsapp')
        self.assertEqual(body['to'], '224620000001')
        self.assertEqual(body['template']['name'], 'booking_reminder')
        self.assertEqual(
            body['template']['components'][0]['parameters'][0]['text'],
            'Votre table vous attend a 20h',
        )

    def test_without_a_template_it_refuses_rather_than_guessing(self):
        """A free-form first message is silently dropped by Meta, which is
        worse than an error somebody can read."""
        with override_settings(WHATSAPP={**WHATSAPP, 'template': ''}):
            with self.assertRaises(NotificationError):
                WhatsAppNotifier(session=FakeSession()).send('620000001', '', 'x')

    def test_without_credentials_it_refuses(self):
        with override_settings(WHATSAPP={**WHATSAPP, 'token': ''}):
            with self.assertRaises(NotificationError):
                WhatsAppNotifier(session=FakeSession()).send('620000001', '', 'x')

    def test_a_refusal_becomes_a_notification_error(self):
        session = FakeSession(FakeResponse(400, text='bad template'))

        with self.assertRaises(NotificationError):
            WhatsAppNotifier(session=session).send('620000001', '', 'x')
