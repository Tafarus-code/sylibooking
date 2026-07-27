"""CORS behaviour for the Flutter web builds.

`flutter run -d chrome` serves from http://localhost:<random port>, so every
request to the API is cross-origin and the browser sends a preflight OPTIONS
first. Without the headers below, Chrome blocks the request before Django ever
sees the POST.
"""

from django.test import TestCase, override_settings
from django.urls import reverse

# A port Flutter picked on a real run — the point is that it is arbitrary.
FLUTTER_ORIGIN = 'http://localhost:58966'


@override_settings(CORS_ALLOW_ALL_ORIGINS=True, CORS_ALLOWED_ORIGINS=[])
class CorsPreflightTests(TestCase):
    """The development posture, pinned.

    These must not read whichever DJANGO_ENV the suite happens to run under —
    CI runs it twice, once as local and once as production.
    """

    def preflight(self, path, origin=FLUTTER_ORIGIN, method='POST'):
        return self.client.options(
            path,
            HTTP_ORIGIN=origin,
            HTTP_ACCESS_CONTROL_REQUEST_METHOD=method,
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS='content-type',
        )

    def assertOriginAllowed(self, response, origin=FLUTTER_ORIGIN):
        """With allow-all and no credentials the header is `*`, not an echo.

        Either satisfies the browser; asserting on one exact value would make
        the test about the library's phrasing rather than the behaviour.
        """
        header = response.headers.get('Access-Control-Allow-Origin')
        self.assertIn(header, ['*', origin], f'origin {origin} was not allowed')

    def test_login_preflight_is_allowed(self):
        response = self.preflight(reverse('auth-login'))

        self.assertEqual(response.status_code, 200)
        self.assertOriginAllowed(response)

    def test_preflight_allows_the_authorization_header(self):
        """Every authenticated call sends `Authorization: Token ...`."""
        response = self.client.options(
            reverse('reservation-list'),
            HTTP_ORIGIN=FLUTTER_ORIGIN,
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='GET',
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS='authorization',
        )

        allowed = response.headers.get('Access-Control-Allow-Headers', '')
        self.assertIn('authorization', allowed.lower())

    def test_actual_request_carries_the_header(self):
        """The preflight passing is useless if the real response lacks it."""
        response = self.client.get(
            reverse('establishment-list'), HTTP_ORIGIN=FLUTTER_ORIGIN
        )

        self.assertEqual(response.status_code, 200)
        self.assertOriginAllowed(response)

    def test_any_localhost_port_works_in_development(self):
        """Flutter picks a new port every run; none of them may be special."""
        for port in [1234, 49876, 58966]:
            with self.subTest(port=port):
                origin = f'http://localhost:{port}'
                response = self.client.get(
                    reverse('establishment-list'), HTTP_ORIGIN=origin
                )
                self.assertOriginAllowed(response, origin)


@override_settings(CORS_ALLOW_ALL_ORIGINS=False, CORS_ALLOWED_ORIGINS=[])
class CorsProductionTests(TestCase):
    """Production fails closed: an unlisted origin gets no header."""

    def test_unlisted_origin_is_refused(self):
        response = self.client.get(
            reverse('establishment-list'),
            HTTP_ORIGIN='https://not-our-app.example.com',
        )

        self.assertIsNone(response.headers.get('Access-Control-Allow-Origin'))

    def test_listed_origin_is_allowed(self):
        with self.settings(CORS_ALLOWED_ORIGINS=['https://app.sylibooking.com']):
            response = self.client.get(
                reverse('establishment-list'),
                HTTP_ORIGIN='https://app.sylibooking.com',
            )

        self.assertEqual(
            response.headers.get('Access-Control-Allow-Origin'),
            'https://app.sylibooking.com',
        )
