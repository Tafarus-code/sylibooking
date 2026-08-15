"""The project's own deployment checks.

Worth testing because they are the last thing between a misconfiguration and
a customer paying for a booking that never confirms — and because the first
version of this guard raised at import, which broke the very command whose
job is to report it.
"""

import os
import tempfile
from unittest import mock

from config.checks import (
    cache_must_be_shared,
    cors_origins_need_a_scheme,
    database_must_be_configured,
    media_domain_must_not_have_a_scheme,
    payment_callbacks_need_secrets,
    push_needs_its_credentials,
)
from django.test import TestCase, override_settings

LOCMEM = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'test',
    }
}
REDIS = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': 'redis://localhost:6379/1',
    }
}


class SharedCacheCheckTests(TestCase):
    @override_settings(DJANGO_ENV='production', CACHES=LOCMEM)
    def test_a_per_process_cache_in_production_is_an_error(self):
        """**The one that costs money.**

        The in-flight Orange pay_token is written by one worker and read by
        another; per-process, the second never finds it and the payment can
        never be settled.
        """
        problems = cache_must_be_shared(None)

        self.assertEqual(len(problems), 1)
        self.assertEqual(problems[0].id, 'sylibooking.E001')
        self.assertIn('CELERY_BROKER_URL', problems[0].hint)

    @override_settings(DJANGO_ENV='production', CACHES=REDIS)
    def test_a_shared_cache_passes(self):
        self.assertEqual(cache_must_be_shared(None), [])

    @override_settings(DJANGO_ENV='local', CACHES=LOCMEM)
    def test_development_is_left_alone(self):
        """There is one process and no Redis to install."""
        self.assertEqual(cache_must_be_shared(None), [])


class CallbackSecretCheckTests(TestCase):
    MOCK = {
        'orange_money': 'payments.providers.MockPaymentProvider',
        'mtn_money': 'payments.providers.MockPaymentProvider',
    }
    LIVE = {
        'orange_money': 'payments.orange.OrangeMoneyProvider',
        'mtn_money': 'payments.mtn.MtnMoneyProvider',
    }

    @override_settings(DJANGO_ENV='production', PAYMENT_PROVIDERS=MOCK)
    def test_the_mock_needs_no_secret(self):
        """It has no callbacks to guard."""
        self.assertEqual(payment_callbacks_need_secrets(None), [])

    @override_settings(
        DJANGO_ENV='production',
        PAYMENT_PROVIDERS=LIVE,
        ORANGE_CALLBACK_SECRET='',
        MTN_CALLBACK_SECRET='',
    )
    def test_a_live_provider_without_its_secret_is_an_error(self):
        """The endpoint refuses everything without it, which is safe and
        silent — so payments would settle only by polling and nobody would
        know why the notification URL does nothing."""
        problems = payment_callbacks_need_secrets(None)

        self.assertEqual(len(problems), 2)
        self.assertTrue(all(p.id == 'sylibooking.E002' for p in problems))

    @override_settings(
        DJANGO_ENV='production',
        PAYMENT_PROVIDERS=LIVE,
        ORANGE_CALLBACK_SECRET='set',
        MTN_CALLBACK_SECRET='set',
    )
    def test_both_configured_passes(self):
        self.assertEqual(payment_callbacks_need_secrets(None), [])

    @override_settings(
        DJANGO_ENV='production',
        PAYMENT_PROVIDERS={
            'orange_money': 'payments.orange.OrangeMoneyProvider',
            'mtn_money': 'payments.providers.MockPaymentProvider',
        },
        ORANGE_CALLBACK_SECRET='',
        MTN_CALLBACK_SECRET='',
    )
    def test_only_the_live_provider_is_complained_about(self):
        """Turning one on at a time is the recommended order, so half-live is
        a normal state rather than a mistake."""
        problems = payment_callbacks_need_secrets(None)

        self.assertEqual(len(problems), 1)
        self.assertIn('Orange', problems[0].msg)

    @override_settings(DJANGO_ENV='local', PAYMENT_PROVIDERS=LIVE)
    def test_development_is_left_alone(self):
        self.assertEqual(payment_callbacks_need_secrets(None), [])


class StorageIndependenceTests(TestCase):
    """Static storage must not depend on where media is kept.

    They were one block once. Turning USE_S3_MEDIA on also switched static
    files to the manifest backend — and the image collects static with media
    storage off, so no manifest was ever written. The first deploy with R2
    enabled answered 500 to every HTML page while the JSON API kept working,
    which is a confusing way to learn that a photo setting decides how CSS is
    served.
    """

    def test_the_static_backend_is_the_same_either_way(self):
        from django.conf import settings

        # Whatever this deployment does with media, the collect that happened
        # at build time and the storage that reads it at runtime agree.
        self.assertIn(
            'ManifestStaticFilesStorage',
            settings.STORAGES['staticfiles']['BACKEND'],
        )

    def test_media_storage_is_the_only_thing_use_s3_media_decides(self):
        """Named so the coupling cannot come back by accident."""
        import config.settings as conf

        self.assertIn('BACKEND', conf._media_storage)
        self.assertNotIn('staticfiles', conf._media_storage)


class DatabaseCheckTests(TestCase):
    CONFIGURED = {'default': {'ENGINE': 'x', 'NAME': 'sylibooking'}}
    MISSING = {'default': {'ENGINE': 'x', 'NAME': ''}}

    @override_settings(DJANGO_ENV='production', DATABASES=MISSING)
    def test_an_unconfigured_database_names_the_variable_people_set(self):
        """**The message this replaces pointed at the wrong variable.**

        It raised about DB_NAME — which nobody sets on a platform that hands
        out DATABASE_URL — and did it as an import-time traceback rather than
        a line somebody could act on.
        """
        problems = database_must_be_configured(None)

        self.assertEqual(len(problems), 1)
        self.assertEqual(problems[0].id, 'sylibooking.E003')
        self.assertIn('DATABASE_URL', problems[0].hint)

    @override_settings(DJANGO_ENV='production', DATABASES=CONFIGURED)
    def test_a_configured_database_passes(self):
        self.assertEqual(database_must_be_configured(None), [])

    @override_settings(DJANGO_ENV='local', DATABASES=MISSING)
    def test_development_is_left_alone(self):
        self.assertEqual(database_must_be_configured(None), [])


class CorsOriginCheckTests(TestCase):
    """A bare hostname in CORS_ALLOWED_ORIGINS matches nothing.

    The symptom is a browser blocking a response the server reports as 200,
    which sends people looking at the API rather than at one variable.
    """

    @override_settings(
        DJANGO_ENV='production',
        CORS_ALLOWED_ORIGINS=['merchant.example.com'],
    )
    def test_a_scheme_less_origin_is_reported(self):
        problems = cors_origins_need_a_scheme(None)

        self.assertEqual(len(problems), 1)
        self.assertEqual(problems[0].id, 'sylibooking.W005')
        self.assertIn('merchant.example.com', problems[0].msg)

    @override_settings(
        DJANGO_ENV='production',
        CORS_ALLOWED_ORIGINS=[
            'https://merchant.example.com',
            'http://localhost:8080',
        ],
    )
    def test_proper_origins_pass(self):
        """http is legitimate — it is how localhost is served."""
        self.assertEqual(cors_origins_need_a_scheme(None), [])

    @override_settings(DJANGO_ENV='production', CORS_ALLOWED_ORIGINS=[])
    def test_nothing_configured_is_not_a_problem_here(self):
        """An empty list is a different decision, not a malformed one."""
        self.assertEqual(cors_origins_need_a_scheme(None), [])

    @override_settings(
        DJANGO_ENV='local', CORS_ALLOWED_ORIGINS=['merchant.example.com']
    )
    def test_development_is_left_alone(self):
        self.assertEqual(cors_origins_need_a_scheme(None), [])


class MediaDomainCheckTests(TestCase):
    """A scheme on MEDIA_CUSTOM_DOMAIN makes every photo URL unopenable.

    `https://https://bucket/photo.jpg` is malformed enough that the browser
    never sends a request, so nothing 404s and nothing is logged anywhere —
    the gallery is simply blank while every part of the system reports
    success.
    """

    PROD = {'DJANGO_ENV': 'production', 'USE_S3_MEDIA': True}

    def check_with(self, value):
        with mock.patch.dict(os.environ, {'MEDIA_CUSTOM_DOMAIN': value}):
            return media_domain_must_not_have_a_scheme(None)

    @override_settings(**PROD)
    def test_a_domain_carrying_https_is_reported(self):
        problems = self.check_with('https://pub-abc123.r2.dev')

        self.assertEqual(len(problems), 1)
        self.assertEqual(problems[0].id, 'sylibooking.W006')
        self.assertIn('pub-abc123.r2.dev', problems[0].msg)

    @override_settings(**PROD)
    def test_http_is_reported_too(self):
        self.assertEqual(len(self.check_with('http://media.example.gn')), 1)

    @override_settings(**PROD)
    def test_a_trailing_slash_is_reported(self):
        """It doubles the separator, which is a different key in the bucket."""
        self.assertEqual(len(self.check_with('media.example.gn/')), 1)

    @override_settings(**PROD)
    def test_a_bare_host_passes(self):
        self.assertEqual(self.check_with('media.example.gn'), [])

    @override_settings(**PROD)
    def test_an_r2_public_host_passes(self):
        self.assertEqual(self.check_with('pub-abc123.r2.dev'), [])

    @override_settings(**PROD)
    def test_nothing_configured_is_not_a_problem_here(self):
        """Unset is a different decision — django-storages then signs URLs."""
        self.assertEqual(self.check_with(''), [])

    @override_settings(DJANGO_ENV='production', USE_S3_MEDIA=False)
    def test_the_check_is_silent_without_s3(self):
        """On container disk there is no custom domain to get wrong."""
        self.assertEqual(self.check_with('https://media.example.gn'), [])

    @override_settings(DJANGO_ENV='local', USE_S3_MEDIA=True)
    def test_development_is_left_alone(self):
        self.assertEqual(self.check_with('https://media.example.gn'), [])


class PushCredentialsCheckTests(TestCase):
    FIREBASE = 'notifications.push.FirebasePushSender'
    CONSOLE = 'notifications.push.ConsolePushSender'

    @override_settings(DJANGO_ENV='production', PUSH_SENDER=FIREBASE)
    @mock.patch.dict(os.environ, {'GOOGLE_APPLICATION_CREDENTIALS': ''})
    def test_firebase_without_credentials_warns(self):
        """Reported, but never fatal.

        Silent failure is what this was written to catch — every push fails,
        nothing is logged where anybody looks, and nobody complains about a
        reminder they never expected. But a notification feature must not be
        able to take the API down with it, so it warns and the sender falls
        back to logging.
        """
        problems = push_needs_its_credentials(None)

        self.assertEqual(len(problems), 1)
        self.assertEqual(problems[0].id, 'sylibooking.W004')
        self.assertIn('FIREBASE_SERVICE_ACCOUNT', problems[0].hint)

    @override_settings(DJANGO_ENV='production', PUSH_SENDER=FIREBASE)
    @mock.patch.dict(os.environ, {'GOOGLE_APPLICATION_CREDENTIALS': ''})
    def test_it_does_not_stop_the_container(self):
        """**The point of the downgrade.**

        The entrypoint runs `check --deploy --fail-level ERROR`, so anything
        at Warning lets the deploy proceed. A venue can take bookings all
        evening without alerts and none at all without the API.
        """
        from django.core.checks import Warning as CheckWarning

        problems = push_needs_its_credentials(None)

        self.assertIsInstance(problems[0], CheckWarning)

    @override_settings(DJANGO_ENV='production', PUSH_SENDER=CONSOLE)
    def test_the_console_sender_needs_nothing(self):
        self.assertEqual(push_needs_its_credentials(None), [])

    @override_settings(DJANGO_ENV='production', PUSH_SENDER=FIREBASE)
    def test_a_readable_credentials_file_passes(self):
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as handle:
            handle.write(b'{}')
            path = handle.name
        self.addCleanup(os.unlink, path)

        with mock.patch.dict(
            os.environ, {'GOOGLE_APPLICATION_CREDENTIALS': path}
        ):
            self.assertEqual(push_needs_its_credentials(None), [])

    @override_settings(DJANGO_ENV='local', PUSH_SENDER=FIREBASE)
    def test_development_is_left_alone(self):
        self.assertEqual(push_needs_its_credentials(None), [])
