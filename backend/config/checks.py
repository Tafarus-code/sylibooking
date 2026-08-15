"""Deployment checks this project needs and Django does not ship.

Django's `--deploy` checks cover the settings it knows about — cookies, HSTS,
DEBUG. These cover the ones that are ours, and they exist as *checks* rather
than as exceptions at import for a reason worth stating: a configuration
problem should be reported by the command whose job is reporting
configuration problems. Raising at import turns `check --deploy` into a
traceback, which is the one output that cannot list a second problem.

Registered against the `deploy` tag, so they run in CI and in the container's
entrypoint and stay out of the way of ordinary work.
"""

from django.conf import settings
from django.core.checks import Error, Tags, register


@register(Tags.caches, deploy=True)
def cache_must_be_shared(app_configs, **kwargs):
    """Production needs a cache every worker can see.

    Two things live in it, and both are wrong when each process has its own:

    * **Throttle counters.** A limit of "5 an hour" silently becomes five an
      hour *per worker*, so the ceiling multiplies by however many processes
      happen to be running.
    * **In-flight Orange Money context.** The `pay_token` is written when a
      payment is started and read when its status is checked — different
      requests, landing on different workers. A worker that cannot find it
      can never settle the payment, so the customer pays and the booking
      stays pending forever.

    The second is the one that costs somebody money, which is why this is an
    Error rather than a Warning.
    """
    if getattr(settings, 'DJANGO_ENV', '') != 'production':
        return []

    backend = settings.CACHES.get('default', {}).get('BACKEND', '')
    if 'locmem' not in backend.lower():
        return []

    return [
        Error(
            'The cache is per-process, and production needs a shared one.',
            hint=(
                'Set CELERY_BROKER_URL (or REDIS_URL) to your Redis instance. '
                'Throttle counters and in-flight payment context both live in '
                'the cache, and a per-process cache makes a payment '
                'unsettleable once a second worker exists.'
            ),
            id='sylibooking.E001',
        )
    ]


@register(Tags.security, deploy=True)
def payment_callbacks_need_secrets(app_configs, **kwargs):
    """A live payment provider needs its callback secret set.

    The callback view already refuses everything when the secret is empty,
    which is the safe direction — but it fails silently, and the symptom is
    payments that only ever settle by polling. Better to say so at deploy
    time than to have somebody wonder why the notification URL does nothing.
    """
    if getattr(settings, 'DJANGO_ENV', '') != 'production':
        return []

    problems = []
    live = {
        'orange_money': ('ORANGE_CALLBACK_SECRET', 'Orange Money'),
        'mtn_money': ('MTN_CALLBACK_SECRET', 'MTN Mobile Money'),
    }
    for provider, (setting_name, label) in live.items():
        adapter = settings.PAYMENT_PROVIDERS.get(provider, '')
        # Only when a real adapter is configured. The mock has no callbacks.
        if 'Mock' in adapter:
            continue
        if not getattr(settings, setting_name, ''):
            problems.append(
                Error(
                    f'{label} is live but {setting_name} is not set.',
                    hint=(
                        'The callback endpoint refuses every request without '
                        'it, so payments would settle only by polling. Set it '
                        'to the same secret that appears in the notification '
                        'URL given to the provider.'
                    ),
                    id='sylibooking.E002',
                )
            )
    return problems


@register(Tags.database, deploy=True)
def database_must_be_configured(app_configs, **kwargs):
    """Production needs a database, and needs to say so usefully.

    The failure this replaces was an import-time exception naming `DB_NAME`
    — a variable nobody sets on a platform that hands out `DATABASE_URL`.
    The message pointed at the fallback rather than at the thing that was
    actually missing, and it arrived as a traceback rather than as a line.
    """
    if getattr(settings, 'DJANGO_ENV', '') != 'production':
        return []

    if settings.DATABASES.get('default', {}).get('NAME'):
        return []

    return [
        Error(
            'No database is configured.',
            hint=(
                'Set DATABASE_URL — Railway, Render and Fly all provide one, '
                'and on Railway it is a reference to the Postgres service '
                '(check the service name matches; a wrong reference resolves '
                'to empty rather than failing). Or set DB_NAME, DB_USER and '
                'DB_PASSWORD individually.'
            ),
            id='sylibooking.E003',
        )
    ]


@register(Tags.compatibility, deploy=True)
def push_needs_its_credentials(app_configs, **kwargs):
    """A Firebase sender with no key sends nothing, and says so to nobody.

    The failure is silent by construction: notifications are logged as failed
    and no customer complains about a reminder they never expected. Worth
    catching at boot rather than discovering from a merchant who says the app
    never tells them anything.
    """
    import os

    if getattr(settings, 'DJANGO_ENV', '') != 'production':
        return []

    sender = getattr(settings, 'PUSH_SENDER', '')
    if 'Firebase' not in sender:
        return []

    path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS', '')
    if path and os.path.exists(path):
        return []

    return [
        Error(
            'Push is set to Firebase but its credentials are not readable.',
            hint=(
                'Set FIREBASE_SERVICE_ACCOUNT to the service account JSON — '
                'the entrypoint writes it to GOOGLE_APPLICATION_CREDENTIALS '
                'at boot. Without it every push fails silently, which is the '
                'one failure nobody reports.'
            ),
            id='sylibooking.E004',
        )
    ]
