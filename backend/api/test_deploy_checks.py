"""The project's own deployment checks.

Worth testing because they are the last thing between a misconfiguration and
a customer paying for a booking that never confirms — and because the first
version of this guard raised at import, which broke the very command whose
job is to report it.
"""

from config.checks import cache_must_be_shared, payment_callbacks_need_secrets
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
