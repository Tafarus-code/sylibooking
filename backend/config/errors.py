"""Where an unhandled exception goes.

Sentry when there is a DSN, the log when there is not — and the second case
is not a degraded mode, it is the normal one for local work and for CI. A
project that only reports errors when a paid service is configured tends to
discover, on the day it is configured, that the reporting call itself was
never exercised.

The same shape as the payment provider and the SMS notifier: an interface, a
real implementation behind a setting, and a console implementation that runs
everywhere else. Slice 11 will do this again for Orange Money.
"""

import logging

from django.conf import settings

logger = logging.getLogger(__name__)


class LoggingReporter:
    """Writes the exception to the log and gets on with it.

    Not a placeholder to be replaced later: in production the log is shipped
    and indexed anyway, so this is a real destination that happens to cost
    nothing.
    """

    name = 'logging'

    def capture(self, error, **context):
        logger.exception('Unhandled: %s', error, extra=context)


class SentryReporter:
    """The real one, when a DSN is set.

    Imported inside the constructor so the dependency is only needed by
    deployments that use it — a local checkout should not have to install an
    error reporter to run the tests.
    """

    name = 'sentry'

    def __init__(self, dsn, environment):
        import sentry_sdk

        sentry_sdk.init(
            dsn=dsn,
            environment=environment,
            # Errors, not performance traces. Traces are the expensive half
            # and nobody here is chasing a slow endpoint yet.
            traces_sample_rate=0,
            # Names and phone numbers are the whole of what this app knows
            # about a person; none of it belongs in a crash report.
            send_default_pii=False,
        )
        self._sdk = sentry_sdk

    def capture(self, error, **context):
        with self._sdk.push_scope() as scope:
            for key, value in context.items():
                scope.set_tag(key, value)
            self._sdk.capture_exception(error)


_reporter = None


def get_reporter():
    """The configured reporter, built once.

    Falls back to the log if Sentry is asked for but cannot be built — a
    missing package or a malformed DSN must not be the reason an error goes
    unreported, which is precisely the moment reporting matters.
    """
    global _reporter
    if _reporter is not None:
        return _reporter

    dsn = getattr(settings, 'SENTRY_DSN', '')
    if dsn:
        try:
            _reporter = SentryReporter(dsn, getattr(settings, 'DJANGO_ENV', ''))
            return _reporter
        except Exception:  # noqa: BLE001
            logger.exception('Could not start Sentry; falling back to the log')

    _reporter = LoggingReporter()
    return _reporter


def report(error, **context):
    """Report one exception. Never raises."""
    try:
        get_reporter().capture(error, **context)
    except Exception:  # noqa: BLE001
        # An error reporter that can throw turns one failure into two, and
        # the second one has no reporter left to catch it.
        logger.exception('The error reporter itself failed')
