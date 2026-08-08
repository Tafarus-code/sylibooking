"""Sending a push, or standing ready to.

The same shape as the SMS notifier and the payment provider: an interface, a
real implementation behind configuration, and a console one that runs
everywhere else. Firebase needs a project and a service account that this
repository does not have, so the console implementation is what runs until
somebody creates one — and because it runs, the code path around it is
exercised on every test rather than on the day credentials appear.
"""

import logging
from abc import ABC, abstractmethod

from django.conf import settings
from django.utils.module_loading import import_string

logger = logging.getLogger(__name__)


class PushError(Exception):
    """The push could not be handed to the service."""


class PushSender(ABC):
    @abstractmethod
    def send(self, tokens, title, body, data=None):
        """Deliver to each token. Returns the tokens that were rejected.

        Rejected is not the same as failed: Firebase reports a token as
        unregistered when the app has been uninstalled or the phone wiped,
        and those should be deleted rather than retried forever.
        """


class ConsolePushSender(PushSender):
    """Prints. What development runs on until a Firebase project exists."""

    def send(self, tokens, title, body, data=None):
        for token in tokens:
            logger.info(
                'Push to %s: %s — %s', token[:12] + '…', title, body
            )
        print(f'\n[PUSH x{len(tokens)}] {title}: {body}\n')  # noqa: T201
        return []


class FirebasePushSender(PushSender):
    """The real one. Needs GOOGLE_APPLICATION_CREDENTIALS and a project.

    Imported lazily so a checkout without the Firebase SDK still runs — the
    dependency belongs to deployments that have a project, not to everybody.
    """

    def __init__(self):
        import firebase_admin
        from firebase_admin import messaging

        if not firebase_admin._apps:
            firebase_admin.initialize_app()
        self._messaging = messaging

    def send(self, tokens, title, body, data=None):
        if not tokens:
            return []

        message = self._messaging.MulticastMessage(
            notification=self._messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            tokens=list(tokens),
        )
        try:
            response = self._messaging.send_each_for_multicast(message)
        except Exception as error:  # noqa: BLE001
            raise PushError(str(error)) from error

        # Tokens Firebase says it has never heard of, or will not hear of
        # again. Returned so the caller can delete them: a token for a wiped
        # phone otherwise stays in the table forever, and every future alert
        # pays to send to it.
        dead = []
        for token, result in zip(tokens, response.responses, strict=False):
            if result.success:
                continue
            code = getattr(result.exception, 'code', '')
            code = str(code)
            if 'registration-token-not-registered' in code or 'invalid' in code:
                dead.append(token)
            else:
                logger.warning('Push to %s failed: %s', token[:12], result.exception)
        return dead


def get_push_sender():
    """The configured sender, built fresh each call.

    Not cached: the Firebase SDK holds a connection, and a cached sender that
    was built before credentials rotated is a class of failure that only
    shows up in production.
    """
    path = getattr(
        settings,
        'PUSH_SENDER',
        'notifications.push.ConsolePushSender',
    )
    return import_string(path)()


def push_to_user(user, title, body, data=None):
    """Every device that account has registered.

    A venue often has a tablet on the counter and a phone in a pocket. An
    alert that reaches only one of them is worse than none, because whoever
    is holding the other believes they are covered.
    """
    from .devices import DeviceToken

    tokens = list(
        DeviceToken.objects.filter(user=user).values_list('token', flat=True)
    )
    if not tokens:
        return 0

    dead = get_push_sender().send(tokens, title, body, data)
    if dead:
        DeviceToken.objects.filter(token__in=dead).delete()
    return len(tokens) - len(dead)
