"""Prove the media bucket round-trips, and say which half is broken.

Every media misconfiguration this project has met failed the same way: the
write succeeded, the row was written, the API answered 200 with a URL in it,
and the picture never appeared. Nothing raises, nothing is logged, and the
symptom — a blank frame in an app — is three layers away from the setting
that caused it.

The reason it stays quiet is that writing and reading go to different places
by design. Uploads go to the S3 API endpoint with credentials; browsers read
from the public domain in front of the bucket, unauthenticated. Those are
two settings pointing at what has to be one bucket, and nothing in Django
compares them: name a bucket in one and a different bucket's public address
in the other and both halves work perfectly, separately, forever.

So this does the round trip. It writes a small object through the configured
storage, fetches it back over the public URL exactly as a browser would, and
reports what happened at each step.
"""

import uuid

import requests
from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand

#: One transparent GIF. Small enough to be free, and a real image so a bucket
#: that inspects content types has nothing to object to.
PROBE = bytes.fromhex(
    '47494638396101000100800000000000ffffff21f90401000000002c000000'
    '000100010000020144003b'
)

TIMEOUT = 15


class Command(BaseCommand):
    help = 'Write a probe image to media storage and read it back publicly.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--origin',
            default='',
            help=(
                'A web app origin to test CORS with, e.g. '
                'https://merchant.example.com. Browsers fetch images by XHR '
                'in Flutter web, so a bucket with no CORS policy blocks every '
                'picture while serving it perfectly to curl.'
            ),
        )
        parser.add_argument(
            '--keep',
            action='store_true',
            help='Leave the probe object in the bucket instead of deleting it.',
        )

    def handle(self, *args, **options):
        ok = self.stdout.write
        backend = settings.STORAGES['default']['BACKEND']

        ok(f'storage      {backend}')
        if not getattr(settings, 'USE_S3_MEDIA', False):
            ok('')
            ok(
                'USE_S3_MEDIA is off, so uploads go to the container disk and '
                'there is no bucket to check. That is correct for local work '
                'and data loss in production — see DEPLOYMENT.md.'
            )
            return

        options_ = settings.STORAGES['default'].get('OPTIONS', {})
        ok(f'bucket       {options_.get("bucket_name")}')
        ok(f'endpoint     {options_.get("endpoint_url")}')
        ok(f'read domain  {options_.get("custom_domain")}')
        ok('')

        name = f'_probe/{uuid.uuid4().hex}.gif'

        # Step one: the write. Credentialed, to the S3 API endpoint.
        try:
            stored = default_storage.save(name, ContentFile(PROBE, name=name))
        except Exception as error:  # noqa: BLE001
            self.fail(
                'the write failed',
                str(error),
                'Check AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and that the '
                'token has Object Read & Write on this bucket.',
            )
            return

        ok(self.style.SUCCESS(f'write  ok   {stored}'))

        # Step two: the read. Anonymous, from the public domain — which is a
        # different address, and the whole reason this command exists.
        url = default_storage.url(stored)
        ok(f'url         {url}')

        headers = {'Origin': options['origin']} if options['origin'] else {}
        try:
            response = requests.get(url, headers=headers, timeout=TIMEOUT)
        except requests.RequestException as error:
            self.fail(
                'the read could not be attempted',
                str(error),
                'The URL above is what the apps are given. If it looks '
                'malformed, MEDIA_CUSTOM_DOMAIN is the setting that built it.',
            )
        else:
            self.report_read(response, options['origin'])

        if not options['keep']:
            default_storage.delete(stored)

    def report_read(self, response, origin):
        ok = self.stdout.write

        if response.status_code == 404:
            self.fail(
                'the read came back 404',
                'The object was written and is not at that URL.',
                'The two halves are pointing at different buckets. The public '
                'address is per bucket, so check the one shown on the bucket '
                'named above and put that in MEDIA_CUSTOM_DOMAIN.',
            )
            return

        if response.status_code in (401, 403):
            self.fail(
                f'the read came back {response.status_code}',
                'The object is there and not publicly readable.',
                'R2 → the bucket → Settings → Public access. On S3, a bucket '
                'policy. Signed URLs are deliberately off: a gallery would '
                'expire halfway through.',
            )
            return

        if response.status_code != 200:
            self.fail(
                f'the read came back {response.status_code}',
                (response.text or '')[:200],
                '',
            )
            return

        ok(self.style.SUCCESS(f'read   ok   {len(response.content)} bytes'))

        if not origin:
            ok('')
            ok(
                'CORS was not tested. Pass --origin https://<the web app> to '
                'check it: the apps fetch images by XHR, so a bucket with no '
                'CORS policy blocks every picture while answering curl fine.'
            )
            return

        allowed = response.headers.get('Access-Control-Allow-Origin', '')
        if allowed in (origin, '*'):
            ok(self.style.SUCCESS(f'cors   ok   {origin}'))
        else:
            self.fail(
                'the bucket sent no usable Access-Control-Allow-Origin',
                f'asked as {origin}, got {allowed!r}',
                'Add a CORS policy allowing that origin for GET and HEAD — '
                'the JSON is in DEPLOYMENT.md. Curl will keep working '
                'without it; the apps will not.',
            )

    def fail(self, headline, detail, hint):
        self.stdout.write(self.style.ERROR(f'FAILED — {headline}'))
        if detail:
            self.stdout.write(f'  {detail}')
        if hint:
            self.stdout.write('')
            self.stdout.write(f'  {hint}')
