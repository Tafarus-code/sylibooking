"""The media round-trip check, which exists because nothing else fails.

Each case here is a misconfiguration that produced blank pictures and no
error anywhere: a write that lands in one bucket and a read that looks in
another, a bucket that is not public, a bucket with no CORS policy. The
command's whole value is telling them apart, so the tests are about which
sentence comes out rather than about whether it runs.
"""

from io import StringIO
from unittest import mock

import requests
from django.core.management import call_command
from django.test import SimpleTestCase, override_settings

COMMAND = 'establishments.management.commands.check_media'

S3 = {
    'default': {
        'BACKEND': 'storages.backends.s3.S3Storage',
        'OPTIONS': {
            'bucket_name': 'sylibooking-media',
            'endpoint_url': 'https://acct.r2.cloudflarestorage.com',
            'custom_domain': 'pub-abc123.r2.dev',
        },
    },
    'staticfiles': {'BACKEND': 'x'},
}
DISK = {
    'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage'},
    'staticfiles': {'BACKEND': 'x'},
}


def response(status, headers=None, content=b'gif'):
    reply = requests.Response()
    reply.status_code = status
    reply.headers.update(headers or {})
    reply._content = content
    return reply


class StorageOffTests(SimpleTestCase):
    @override_settings(USE_S3_MEDIA=False, STORAGES=DISK)
    def test_it_says_so_and_asks_nothing_of_the_network(self):
        out = StringIO()

        with mock.patch(f'{COMMAND}.requests.get') as get:
            call_command('check_media', stdout=out)

        self.assertIn('USE_S3_MEDIA is off', out.getvalue())
        get.assert_not_called()


@override_settings(USE_S3_MEDIA=True, STORAGES=S3)
class RoundTripTests(SimpleTestCase):
    def setUp(self):
        self.storage = mock.MagicMock()
        self.storage.save.return_value = '_probe/abc.gif'
        self.storage.url.return_value = 'https://pub-abc123.r2.dev/_probe/abc.gif'

        patcher = mock.patch(f'{COMMAND}.default_storage', self.storage)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_with(self, reply, **options):
        out = StringIO()
        with mock.patch(f'{COMMAND}.requests.get', return_value=reply):
            call_command('check_media', stdout=out, **options)
        return out.getvalue()

    def test_the_settings_it_used_are_printed_before_anything_can_fail(self):
        """Half of diagnosing this is seeing the two addresses side by side."""
        text = self.run_with(response(200))

        self.assertIn('sylibooking-media', text)
        self.assertIn('pub-abc123.r2.dev', text)

    def test_a_working_bucket_reports_both_halves(self):
        text = self.run_with(response(200))

        self.assertIn('write  ok', text)
        self.assertIn('read   ok', text)

    def test_a_404_names_the_mistake_that_causes_it(self):
        """**The one this whole command is for.** Written and not readable
        means the two settings point at different buckets."""
        text = self.run_with(response(404))

        self.assertIn('FAILED', text)
        self.assertIn('different buckets', text)

    def test_a_403_points_at_public_access_instead(self):
        text = self.run_with(response(403))

        self.assertIn('FAILED', text)
        self.assertIn('Public access', text)

    def test_a_failed_write_is_distinguished_from_a_failed_read(self):
        self.storage.save.side_effect = OSError('access denied')
        out = StringIO()

        with mock.patch(f'{COMMAND}.requests.get') as get:
            call_command('check_media', stdout=out)

        self.assertIn('the write failed', out.getvalue())
        # Nothing to read if nothing was written.
        get.assert_not_called()

    def test_a_malformed_url_is_reported_against_the_setting_that_built_it(self):
        out = StringIO()
        with mock.patch(
            f'{COMMAND}.requests.get',
            side_effect=requests.RequestException('invalid URL'),
        ):
            call_command('check_media', stdout=out)

        self.assertIn('MEDIA_CUSTOM_DOMAIN', out.getvalue())

    def test_the_probe_is_cleaned_up(self):
        self.run_with(response(200))

        self.storage.delete.assert_called_once_with('_probe/abc.gif')

    def test_keep_leaves_it_there(self):
        self.run_with(response(200), keep=True)

        self.storage.delete.assert_not_called()


@override_settings(USE_S3_MEDIA=True, STORAGES=S3)
class CorsTests(SimpleTestCase):
    """A bucket serves curl perfectly and the apps not at all.

    Flutter web fetches image bytes by XHR rather than using an <img>, so a
    missing CORS policy blocks every picture — while every check anybody
    reaches for from a terminal says the image is fine.
    """

    ORIGIN = 'https://merchant.example.com'

    def setUp(self):
        storage = mock.MagicMock()
        storage.save.return_value = '_probe/abc.gif'
        storage.url.return_value = 'https://pub-abc123.r2.dev/_probe/abc.gif'
        patcher = mock.patch(f'{COMMAND}.default_storage', storage)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_with(self, reply, origin=ORIGIN):
        out = StringIO()
        with mock.patch(f'{COMMAND}.requests.get', return_value=reply) as get:
            call_command('check_media', stdout=out, origin=origin)
        return out.getvalue(), get

    def test_the_origin_is_actually_sent(self):
        """Asking without the header would pass against any bucket."""
        _, get = self.run_with(response(200))

        self.assertEqual(get.call_args.kwargs['headers']['Origin'], self.ORIGIN)

    def test_a_matching_allow_origin_passes(self):
        text, _ = self.run_with(
            response(200, {'Access-Control-Allow-Origin': self.ORIGIN})
        )

        self.assertIn('cors   ok', text)

    def test_a_wildcard_passes_too(self):
        text, _ = self.run_with(
            response(200, {'Access-Control-Allow-Origin': '*'})
        )

        self.assertIn('cors   ok', text)

    def test_a_readable_image_with_no_cors_header_still_fails(self):
        """200 and unusable. The case that looks like success everywhere."""
        text, _ = self.run_with(response(200))

        self.assertIn('FAILED', text)
        self.assertIn('Access-Control-Allow-Origin', text)

    def test_another_sites_origin_is_not_accepted_as_ours(self):
        text, _ = self.run_with(
            response(200, {'Access-Control-Allow-Origin': 'https://elsewhere'})
        )

        self.assertIn('FAILED', text)

    def test_without_an_origin_cors_is_reported_as_untested(self):
        text, _ = self.run_with(response(200), origin='')

        self.assertIn('CORS was not tested', text)
        self.assertNotIn('FAILED', text)
