"""Is the thing up, and can it do its job?

Two endpoints rather than one, because two different callers ask.

A load balancer asks "should I send traffic here" many times a minute and
wants a cheap yes. Whoever is on call asks "what is broken" once, in a hurry,
and wants the parts listed. Answering both with one expensive endpoint means
either the balancer pays for a database round trip every second or the person
debugging gets a bare "ok" that tells them nothing.
"""

import logging

from django.conf import settings
from django.db import connection
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

logger = logging.getLogger(__name__)


def _check_database():
    """One trivial query. Enough to prove the connection, cheap enough to
    run often."""
    with connection.cursor() as cursor:
        cursor.execute('SELECT 1')
        cursor.fetchone()


def _check_cache():
    """The cache is not decoration here — it holds the throttle counters, so
    losing it silently means the rate limits stop being rate limits."""
    from django.core.cache import cache

    cache.set('health:probe', 'ok', 10)
    if cache.get('health:probe') != 'ok':
        raise RuntimeError('cache wrote but did not read back')


def _check_broker():
    """Celery's queue. Reminders, the no-show sweep and the payment poller
    all run through it, and every one of them fails silently: nobody
    complains that a reminder they never expected did not arrive."""
    from kombu import Connection

    with Connection(settings.CELERY_BROKER_URL) as conn:
        conn.ensure_connection(max_retries=0, timeout=2)


CHECKS = {
    'database': _check_database,
    'cache': _check_cache,
    'broker': _check_broker,
}


class LivenessView(APIView):
    """Is the process answering at all.

    Deliberately touches nothing. A liveness probe that checks the database
    will restart a healthy web server because Postgres hiccuped, which turns
    one outage into two.
    """

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = []

    def get(self, request):
        return Response({'status': 'ok'})


class ReadinessView(APIView):
    """What works and what does not, part by part.

    503 when anything is down, because that is the answer a balancer acts on
    — but the body still lists every part, because the 503 is also what wakes
    somebody up and "which one" is their first question.

    Each check is caught separately: one failure must not hide the state of
    the others, and knowing that the database is fine while the broker is
    gone is most of the diagnosis.
    """

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = []

    def get(self, request):
        parts = {}
        for name, check in CHECKS.items():
            try:
                check()
                parts[name] = {'ok': True}
            except Exception as error:  # noqa: BLE001 — the point is to report
                logger.warning('Health check %s failed: %s', name, error)
                parts[name] = {'ok': False, 'error': str(error)[:200]}

        healthy = all(part['ok'] for part in parts.values())
        return Response(
            {'status': 'ok' if healthy else 'degraded', 'checks': parts},
            status=200 if healthy else 503,
        )
