"""Real notifiers: an SMS aggregator, and WhatsApp.

Two implementations of the `Notifier` interface in accounts/notifications.py,
so reminders, reset codes and no-show warnings can leave the machine without
anything above this file changing.

**The SMS one is deliberately generic.** Which aggregator serves Guinea is a
commercial decision nobody has made yet, and every one of them offers the same
thing: an HTTP endpoint that takes a destination and a body. Rather than
guessing a vendor and writing an adapter that has to be thrown away, this
takes the URL, the method, the auth header and the field names from settings.
Configuring it for Twilio, Africa's Talking, Orange's own SMS API or a local
reseller is environment variables — see DEPLOYMENT.md for worked examples.

The cost of that generality is one thing it cannot do: understand a vendor's
error codes. It knows "they accepted it" and "they did not", which is what the
retry policy actually acts on.

**WhatsApp is specific**, because there is only one: Meta's Cloud API, whose
shape is fixed and whose template rules are not negotiable. Free-form messages
are only allowed inside a 24-hour window after the customer writes to you, so
anything we send first has to be an approved template. That is a business
process, not a code path, and it is why this refuses rather than guesses when
no template is configured.
"""

import logging

from django.conf import settings

from payments.http import ProviderHttpError, request

from .notifications import NotificationError, Notifier

logger = logging.getLogger(__name__)


def _dig(payload, path):
    """Read `a.b.c` out of a nested response, or None."""
    current = payload
    for part in path.split('.'):
        if not isinstance(current, dict):
            return None
        current = current.get(part)
    return current


class HttpSmsNotifier(Notifier):
    """Any SMS aggregator that speaks HTTP.

    Configured by `SMS_GATEWAY` — see settings for the keys and DEPLOYMENT.md
    for what to put in them.
    """

    def __init__(self, session=None):
        self._session = session

    @property
    def config(self):
        return getattr(settings, 'SMS_GATEWAY', {})

    def send(self, destination, subject, body):
        config = self.config
        url = config.get('url')
        if not url:
            raise NotificationError('No SMS gateway URL is configured.')

        number = _e164(destination, config.get('default_country_code', '224'))
        payload = _fill(
            config.get('payload', {}),
            to=number,
            text=body,
            sender=config.get('sender', ''),
        )

        headers = dict(config.get('headers', {}))
        auth = None
        if config.get('username') or config.get('password'):
            auth = (config.get('username', ''), config.get('password', ''))

        try:
            answer = request(
                config.get('method', 'POST'),
                url,
                session=self._session,
                # Never retried. A retried SMS is a second message and a
                # second charge, and the recipient cannot tell which of the
                # two was the real one.
                idempotent=False,
                headers=headers,
                auth=auth,
                **(
                    {'json': payload}
                    if config.get('encoding', 'json') == 'json'
                    else {'data': payload}
                ),
            )
        except ProviderHttpError as error:
            raise NotificationError(f'SMS gateway refused: {error}') from error

        # Some gateways answer 200 and put the failure in the body. Where a
        # success path is configured, it is checked; where it is not, a 200 is
        # taken at face value.
        success_path = config.get('success_path')
        if success_path:
            value = _dig(answer, success_path)
            expected = config.get('success_value')
            if expected is not None and str(value) != str(expected):
                raise NotificationError(
                    f'SMS gateway reported failure: {answer}'
                )

        logger.info('SMS handed to the gateway for %s', number)
        return answer


class WhatsAppNotifier(Notifier):
    """Meta's WhatsApp Cloud API.

    Sends an approved template, because that is the only thing allowed
    outside a 24-hour reply window — and every message this product sends
    first (a reminder, a confirmation, a reset code) is outside one by
    definition.
    """

    def __init__(self, session=None):
        self._session = session

    @property
    def config(self):
        return getattr(settings, 'WHATSAPP', {})

    def send(self, destination, subject, body):
        config = self.config
        token = config.get('token')
        phone_number_id = config.get('phone_number_id')
        template = config.get('template')

        if not (token and phone_number_id):
            raise NotificationError('WhatsApp is not configured.')
        if not template:
            # Refused rather than guessed: an unapproved template name is
            # rejected by Meta anyway, and a free-form message outside the
            # window is silently dropped, which is worse.
            raise NotificationError(
                'No approved WhatsApp template is configured; a first message '
                'cannot be free-form.'
            )

        number = _e164(destination, config.get('default_country_code', '224'))
        url = (
            f"{config.get('base_url', 'https://graph.facebook.com/v21.0')}"
            f'/{phone_number_id}/messages'
        )

        try:
            return request(
                'POST',
                url,
                session=self._session,
                idempotent=False,
                headers={
                    'Authorization': f'Bearer {token}',
                    'Content-Type': 'application/json',
                },
                json={
                    'messaging_product': 'whatsapp',
                    'to': number,
                    'type': 'template',
                    'template': {
                        'name': template,
                        'language': {
                            'code': config.get('language', 'fr')
                        },
                        # One body parameter, carrying the whole sentence the
                        # rest of the product already composed. A template
                        # with more placeholders needs this to grow, and the
                        # notification that fills them to know about it.
                        'components': [
                            {
                                'type': 'body',
                                'parameters': [
                                    {'type': 'text', 'text': body}
                                ],
                            }
                        ],
                    },
                },
            )
        except ProviderHttpError as error:
            raise NotificationError(f'WhatsApp refused: {error}') from error


def _fill(template, **values):
    """Substitute `{to}`, `{text}` and `{sender}` through a nested payload.

    The payload shape is a vendor's business, so it is data. This walks it and
    replaces the placeholders wherever they appear.
    """
    if isinstance(template, dict):
        return {key: _fill(value, **values) for key, value in template.items()}
    if isinstance(template, list):
        return [_fill(item, **values) for item in template]
    if isinstance(template, str):
        for key, value in values.items():
            template = template.replace('{' + key + '}', str(value))
        return template
    return template


def _e164(destination, country_code):
    """A number in the shape gateways expect: digits, no plus, no spaces.

    A customer types `620 00 00 01` or `+224 620 00 00 01`, and a gateway
    wants one of those. Normalising here means every gateway gets the same
    thing and only one place has to know the country code.
    """
    digits = ''.join(c for c in (destination or '') if c.isdigit())
    if not digits:
        return ''
    if digits.startswith(country_code):
        return digits
    # A local number, written without the country code.
    return f'{country_code}{digits.lstrip("0")}'
