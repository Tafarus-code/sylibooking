"""Log lines a machine can read, without making them unreadable to a person.

Two formatters, chosen by environment rather than by taste.

In development a log line is read by whoever is looking at the terminal, so
it stays plain text. In production nobody reads log lines one at a time —
they are shipped, indexed and searched — and a message like

    Could not send reset code to +224 ••• ••42

is unsearchable the moment the number differs. As JSON, with the fields
beside the message, "every failed send in the last hour" becomes a query
rather than a grep and a guess.

Nothing here changes what the code logs. The existing `logger.exception(...)`
calls throughout the app are the value; this only decides how they come out.
"""

import json
import logging


class JsonFormatter(logging.Formatter):
    """One JSON object per line.

    Deliberately hand-rolled rather than a dependency: the whole contract is
    a dict and a newline, and a logging formatter that can itself fail is a
    bad trade for saving twenty lines.
    """

    #: Attributes LogRecord always carries. Anything else on the record was
    #: put there deliberately by a caller, so it travels with the message.
    _STANDARD = frozenset(
        vars(logging.LogRecord('', 0, '', 0, '', None, None)).keys()
    ) | {'message', 'asctime', 'taskName'}

    def format(self, record):
        payload = {
            'time': self.formatTime(record, '%Y-%m-%dT%H:%M:%S%z'),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
        }

        if record.exc_info:
            payload['exception'] = self.formatException(record.exc_info)

        # Whatever the caller attached via `extra=`. This is what makes a log
        # line queryable: reservation=41 rather than "…for booking 41".
        for key, value in vars(record).items():
            if key not in self._STANDARD and not key.startswith('_'):
                payload[key] = _safe(value)

        return json.dumps(payload, default=str, ensure_ascii=False)


def _safe(value):
    """Anything JSON cannot hold becomes its own repr rather than an
    exception thrown while trying to report an exception."""
    if isinstance(value, (str, int, float, bool, type(None))):
        return value
    return str(value)


def logging_config(*, structured, level):
    """The dict Django expects.

    `disable_existing_loggers` stays False: Django's own loggers are how a
    500 gets recorded at all, and switching them off while adding
    observability would be an unusually direct own goal.
    """
    return {
        'version': 1,
        'disable_existing_loggers': False,
        'formatters': {
            'json': {'()': 'config.logging.JsonFormatter'},
            'plain': {
                'format': '{levelname:<8} {name} {message}',
                'style': '{',
            },
        },
        'handlers': {
            'console': {
                'class': 'logging.StreamHandler',
                'formatter': 'json' if structured else 'plain',
            },
        },
        'root': {'handlers': ['console'], 'level': level},
        'loggers': {
            # Django's request logger is where an unhandled 500 surfaces.
            'django.request': {'level': 'WARNING', 'propagate': True},
            # Every SQL statement at DEBUG is noise that hides the signal.
            'django.db.backends': {'level': 'INFO', 'propagate': True},
        },
    }
