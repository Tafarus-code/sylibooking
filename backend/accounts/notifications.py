"""Getting a message to a customer.

The same shape as the payment providers: one interface, a stub that logs, and
a settings switch. Nothing above this module learns whether the code went out
over a real SMS gateway or into the console — so wiring a Guinean aggregator
later is configuration, not a rewrite.
"""

import logging
from abc import ABC, abstractmethod

from django.conf import settings
from django.core.mail import send_mail
from django.utils.module_loading import import_string

logger = logging.getLogger(__name__)


class NotificationError(Exception):
    """The message could not be handed over.

    Distinct from "the customer never read it": this means we could not even
    place the request, so telling them to check their phone would be a lie.
    """


class Notifier(ABC):
    """Sends one short message to one destination."""

    @abstractmethod
    def send(self, destination, subject, body):
        """Deliver, or raise NotificationError."""


class ConsoleSmsNotifier(Notifier):
    """Prints the message. What development runs on until a gateway exists.

    Deliberately loud and deliberately not silent-by-default: during
    development the code has to be readable somewhere, and the console is the
    honest place for it.
    """

    def send(self, destination, subject, body):
        logger.warning(
            'SMS to %s\n--- would send ---\n%s\n------------------',
            destination,
            body,
        )
        print(f'\n[SMS -> {destination}]\n{body}\n')  # noqa: T201


class EmailNotifier(Notifier):
    """Django's mail backend, which is the console backend in development."""

    def send(self, destination, subject, body):
        try:
            send_mail(
                subject=subject,
                message=body,
                from_email=getattr(
                    settings, 'DEFAULT_FROM_EMAIL', 'no-reply@sylibooking.gn'
                ),
                recipient_list=[destination],
                fail_silently=False,
            )
        except Exception as error:  # noqa: BLE001 - any backend failure
            raise NotificationError(str(error)) from error


def get_notifier(channel):
    """The adapter configured for this channel."""
    backends = getattr(settings, 'NOTIFIERS', {})
    try:
        dotted_path = backends[channel]
    except KeyError:
        raise NotificationError(
            f'No notifier configured for {channel!r}.'
        ) from None
    return import_string(dotted_path)()


def mask(destination):
    """Show enough to recognise, not enough to use.

    "+224 62… 45" tells the right customer they are in the right place, and
    tells someone probing for accounts almost nothing.
    """
    if '@' in destination:
        name, _, domain = destination.partition('@')
        shown = name[:2] if len(name) > 2 else name[:1]
        return f'{shown}{"…"}@{domain}'

    digits = ''.join(ch for ch in destination if ch.isdigit())
    if len(digits) < 4:
        return '…'
    return f'{digits[:4]}…{digits[-2:]}'
