"""The health probes, as a platform actually reaches them.

Railway, Render and Fly all check a container by talking to it directly
rather than through the proxy that terminates TLS. The request therefore
arrives as plain http with no `X-Forwarded-Proto`, and a production Django
answers 301 — which the platform reads as unhealthy, restarts a working
container over, and repeats.

These run with the production redirect turned on explicitly, because the
suite otherwise disables it and would prove nothing.
"""

from django.test import TestCase, override_settings
from django.urls import reverse


@override_settings(
    SECURE_SSL_REDIRECT=True,
    SECURE_REDIRECT_EXEMPT=[r'^api/health/'],
    SECURE_PROXY_SSL_HEADER=('HTTP_X_FORWARDED_PROTO', 'https'),
)
class HealthProbeTests(TestCase):
    def test_liveness_answers_over_plain_http(self):
        """**The check that was failing on Railway.**

        A 301 here is a container restarted forever for being healthy.
        """
        response = self.client.get(reverse('health'))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['status'], 'ok')

    def test_readiness_answers_over_plain_http(self):
        response = self.client.get(reverse('health-ready'))

        # 503 is a legitimate answer — it means a dependency is down, which
        # is the endpoint working. A redirect is not an answer at all.
        self.assertIn(response.status_code, (200, 503))

    def test_everything_else_is_still_redirected(self):
        """The exemption is two paths, not a hole in the policy."""
        response = self.client.get(reverse('establishment-list'))

        self.assertEqual(response.status_code, 301)
        self.assertTrue(response['Location'].startswith('https://'))

    def test_a_proxied_request_is_not_redirected(self):
        """The ordinary path: TLS terminated in front, header set, no
        redirect for anybody."""
        response = self.client.get(
            reverse('establishment-list'), HTTP_X_FORWARDED_PROTO='https'
        )

        self.assertEqual(response.status_code, 200)


class PlatformHostTests(TestCase):
    """A generated domain has to work without anybody setting a variable.

    `RAILWAY_PUBLIC_DOMAIN` is documented but is not always in the process
    environment — notably when the domain is created after the container
    started. The symptom is a service whose health check passes and whose
    public URL answers 400 to everything, which reads as a broken deploy
    rather than a missing variable.
    """

    @override_settings(ALLOWED_HOSTS=['.railway.app'])
    def test_a_generated_railway_domain_is_accepted(self):
        response = self.client.get(
            reverse('health'), HTTP_HOST='api-dev-b806.up.railway.app'
        )

        self.assertEqual(response.status_code, 200)

    @override_settings(ALLOWED_HOSTS=['.railway.app'])
    def test_the_wildcard_does_not_admit_anything_else(self):
        """A family, not a hole: an unrelated host is still refused."""
        response = self.client.get(
            reverse('health'), HTTP_HOST='not-railway.example.com'
        )

        self.assertEqual(response.status_code, 400)
