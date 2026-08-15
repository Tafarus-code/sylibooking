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
from django.core.checks import Error, Tags, Warning, register


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


@register(Tags.security, deploy=True)
def cors_origins_need_a_scheme(app_configs, **kwargs):
    """A browser origin is scheme + host + port, and never a bare hostname.

    django-cors-headers compares `CORS_ALLOWED_ORIGINS` against the browser's
    `Origin` header as an exact string. "merchant.example.com" matches no
    origin any browser will ever send, so the entry is not wrong so much as
    inert — the header is simply never added, and the request fails in the
    browser with the server reporting a perfectly ordinary 200.

    Same shape of mistake as a scheme-less API base URL, and just as quiet:
    nothing in Django, in the settings, or in the response says the value was
    ignored.
    """
    if getattr(settings, 'DJANGO_ENV', '') != 'production':
        return []

    origins = getattr(settings, 'CORS_ALLOWED_ORIGINS', []) or []
    bad = [
        origin
        for origin in origins
        if not origin.startswith(('http://', 'https://'))
    ]
    if not bad:
        return []

    return [
        Warning(
            'CORS_ALLOWED_ORIGINS has entries with no scheme: '
            + ', '.join(repr(origin) for origin in bad),
            hint=(
                'Write each one as the browser sends it — '
                'https://merchant.example.com, with no trailing slash and no '
                'path. An entry without a scheme matches nothing, so the '
                'browser blocks the response while the server logs a 200.'
            ),
            id='sylibooking.W005',
        )
    ]


@register(Tags.files, deploy=True)
def media_domain_must_not_have_a_scheme(app_configs, **kwargs):
    """The mirror of the CORS mistake, and quieter still.

    `MEDIA_CUSTOM_DOMAIN` is a bare host. django-storages builds a photo URL
    as scheme + '//' + custom_domain + key, so a value that brings its own
    scheme yields `https://https://bucket.example/photo.jpg` — malformed
    enough that a browser will not attempt it, which means no request, no
    404, and nothing in any log at either end.

    Every symptom points away from the cause. Uploads succeed, the bucket
    fills, the API answers 200 with a URL in it, and the apps show empty
    frames. Settings corrects the value so the deployment works; this says
    where it came from, so the next deploy does not need correcting.
    """
    if getattr(settings, 'DJANGO_ENV', '') != 'production':
        return []

    if not getattr(settings, 'USE_S3_MEDIA', False):
        return []

    import os

    raw = os.environ.get('MEDIA_CUSTOM_DOMAIN', '').strip()
    if not raw.startswith(('http://', 'https://')) and not raw.endswith('/'):
        return []

    return [
        Warning(
            f'MEDIA_CUSTOM_DOMAIN is a URL, not a host: {raw!r}',
            hint=(
                'Write it as a bare hostname — media.example.com, or '
                'pub-<id>.r2.dev — with no scheme, no trailing slash and no '
                'path. Settings strips those so images still load, but the '
                'variable itself is what the next deploy reads.'
            ),
            id='sylibooking.W006',
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
        # A Warning, not an Error, so `check --deploy --fail-level ERROR` in
        # the entrypoint lets the container start. Push is a feature; the API
        # is the product, and a missing notification key must not be able to
        # take bookings offline. The sender falls back to logging and says so
        # loudly, which keeps this from being the silent failure it was made
        # to catch.
        Warning(
            'Push is set to Firebase but its credentials are not readable.',
            hint=(
                'Set FIREBASE_SERVICE_ACCOUNT to the service account JSON — '
                'the entrypoint writes it to GOOGLE_APPLICATION_CREDENTIALS '
                'at boot. Without it every push fails silently, which is the '
                'one failure nobody reports.'
            ),
            id='sylibooking.W004',
        )
    ]
