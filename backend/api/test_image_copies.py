"""Small copies of uploaded pictures, and what happens when there are none.

The point of these is not that Pillow can resize — it can. It is that every
state a row can be in still serves *something*: a picture too small to shrink,
a row uploaded before any of this existed, and a file nothing can read are all
ordinary, and none of them may be an error on a customer's browse list.
"""

import shutil
import tempfile
from io import BytesIO

from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from establishments.images import CARD_WIDTH, DETAIL_WIDTH, MAX_STORED_WIDTH
from establishments.models import Establishment, MenuItem, Photo

User = get_user_model()

MEDIA = tempfile.mkdtemp()


def photo_bytes(width, height, fmt='JPEG'):
    """A picture of a given size, with enough variation to survive JPEG."""
    image = Image.new('RGB', (width, height))
    for x in range(0, width, 8):
        for y in range(0, height, 8):
            image.putpixel((x, y), ((x * 7) % 255, (y * 3) % 255, 120))
    buffer = BytesIO()
    image.save(buffer, format=fmt)
    return buffer.getvalue()


def upload(width, height, name='photo.jpg'):
    return SimpleUploadedFile(name, photo_bytes(width, height), 'image/jpeg')


def opened(field):
    """Read a stored file from the start, whatever state its handle is in.

    Resizing leaves the field's handle closed, which is correct — it should
    not hold one open — but means a test cannot hand the field straight to
    Pillow.
    """
    field.open()
    try:
        return Image.open(BytesIO(field.read()))
    finally:
        field.close()


@override_settings(MEDIA_ROOT=MEDIA)
class ImageCopyTests(TestCase):
    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(MEDIA, ignore_errors=True)
        super().tearDownClass()

    def setUp(self):
        self.venue = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )

    def make_photo(self, width=1600, height=1200):
        return Photo.objects.create(
            establishment=self.venue,
            uploaded_by_role=Photo.UploaderRole.MERCHANT,
            image=upload(width, height),
        )

    # --- Generating ------------------------------------------------------

    def test_uploading_builds_both_copies(self):
        photo = self.make_photo()

        self.assertTrue(photo.thumbnail)
        self.assertTrue(photo.detail)

    def test_the_copies_are_the_configured_widths(self):
        photo = self.make_photo(1600, 1200)

        self.assertEqual(opened(photo.thumbnail).width, CARD_WIDTH)
        self.assertEqual(opened(photo.detail).width, DETAIL_WIDTH)

    def test_the_copies_keep_the_shape_of_the_original(self):
        # A 4:3 photograph must not come back square.
        photo = self.make_photo(1600, 1200)

        thumbnail = opened(photo.thumbnail)
        self.assertAlmostEqual(
            thumbnail.width / thumbnail.height, 4 / 3, places=1
        )

    def test_a_card_copy_is_far_smaller_than_the_original(self):
        # The entire point of the slice, asserted as a number.
        photo = self.make_photo(2000, 1500)

        self.assertLess(photo.thumbnail.size * 10, photo.image.size)

    def test_the_copies_sit_beside_the_original(self):
        photo = self.make_photo()

        folder = photo.image.name.rsplit('/', 1)[0]
        self.assertTrue(photo.thumbnail.name.startswith(folder))
        self.assertTrue(photo.thumbnail.name.endswith('-thumbnail.jpg'))

    def test_a_menu_picture_gets_the_same_treatment(self):
        item = MenuItem.objects.create(
            establishment=self.venue,
            name='Poulet yassa',
            category=MenuItem.Category.FOOD,
            price='75000.00',
            image=upload(1600, 1200),
        )

        self.assertEqual(opened(item.thumbnail).width, CARD_WIDTH)

    def test_a_picture_smaller_than_the_copy_gets_none(self):
        # Not a failure: the original is already smaller than the derivative
        # would be, so making one would cost bytes rather than save them.
        photo = self.make_photo(200, 150)

        self.assertFalse(photo.thumbnail)
        self.assertFalse(photo.detail)

    def test_a_transparent_png_becomes_an_opaque_jpeg(self):
        photo = Photo.objects.create(
            establishment=self.venue,
            uploaded_by_role=Photo.UploaderRole.MERCHANT,
            image=SimpleUploadedFile(
                'shot.png', photo_bytes(1600, 1200, fmt='PNG'), 'image/png'
            ),
        )

        self.assertEqual(opened(photo.thumbnail).mode, 'RGB')

    def test_saving_again_does_not_rebuild(self):
        photo = self.make_photo()
        first = photo.thumbnail.name

        photo.caption = 'La terrasse'
        photo.save()

        photo.refresh_from_db()
        self.assertEqual(photo.thumbnail.name, first)

    # --- Capping the original --------------------------------------------

    def test_an_oversized_original_is_shrunk_on_the_way_in(self):
        photo = self.make_photo(MAX_STORED_WIDTH + 1200, 1500)

        self.assertEqual(opened(photo.image).width, MAX_STORED_WIDTH)

    def test_the_shrunk_original_keeps_its_name(self):
        # The name is already in the database and on any URL already handed
        # out, so capping must not rename the file.
        photo = self.make_photo(MAX_STORED_WIDTH + 1200, 1500)
        stored = photo.image.name

        photo.refresh_from_db()
        self.assertEqual(photo.image.name, stored)

    def test_an_original_inside_the_cap_is_left_alone(self):
        photo = self.make_photo(1000, 800)

        self.assertEqual(opened(photo.image).width, 1000)

    # --- Serving ----------------------------------------------------------

    def test_the_api_offers_the_small_copy(self):
        self.make_photo()

        response = APIClient().get(
            f'/api/establishments/{self.venue.pk}/photos/'
        )

        row = response.data['results'][0]
        self.assertIn('-thumbnail.jpg', row['thumbnail'])
        self.assertIn('-detail.jpg', row['detail'])
        # The original is still offered, unchanged, for the viewer.
        self.assertNotIn('-thumbnail', row['image'])

    def test_a_row_with_no_copies_still_serves(self):
        """**The migration window.**

        Every picture uploaded before this feature has empty copy fields, and
        the API must answer for them rather than 500. They fall back to the
        original, which is what those clients were fetching anyway.
        """
        photo = self.make_photo()
        Photo.objects.filter(pk=photo.pk).update(thumbnail='', detail='')

        response = APIClient().get(
            f'/api/establishments/{self.venue.pk}/photos/'
        )

        row = response.data['results'][0]
        self.assertEqual(response.status_code, 200)
        self.assertEqual(row['thumbnail'], row['image'])
        self.assertEqual(row['detail'], row['image'])

    def test_a_menu_response_carries_the_thumbnail(self):
        MenuItem.objects.create(
            establishment=self.venue,
            name='Poulet yassa',
            category=MenuItem.Category.FOOD,
            price='75000.00',
            image=upload(1600, 1200),
        )

        response = APIClient().get(f'/api/establishments/{self.venue.pk}/')

        item = response.data['menu'][0]['items'][0]
        self.assertIn('-thumbnail.jpg', item['thumbnail'])

    # --- Backfill ---------------------------------------------------------

    def test_the_backfill_builds_what_is_missing(self):
        photo = self.make_photo()
        Photo.objects.filter(pk=photo.pk).update(thumbnail='', detail='')

        call_command('backfill_image_copies', verbosity=0)

        photo.refresh_from_db()
        self.assertTrue(photo.thumbnail)
        self.assertEqual(opened(photo.thumbnail).width, CARD_WIDTH)

    def test_the_backfill_is_idempotent(self):
        photo = self.make_photo()
        Photo.objects.filter(pk=photo.pk).update(thumbnail='', detail='')

        call_command('backfill_image_copies', verbosity=0)
        photo.refresh_from_db()
        first = photo.thumbnail.name

        call_command('backfill_image_copies', verbosity=0)
        photo.refresh_from_db()

        self.assertEqual(photo.thumbnail.name, first)

    def test_the_backfill_survives_a_file_it_cannot_read(self):
        # A row whose file is missing or corrupt must not stop the run: the
        # rest of the catalogue still wants its copies.
        broken = self.make_photo()
        Photo.objects.filter(pk=broken.pk).update(thumbnail='', detail='')
        broken.image.storage.delete(broken.image.name)
        broken.image.storage.save(
            broken.image.name, ContentFile(b'not an image')
        )

        good = self.make_photo()
        Photo.objects.filter(pk=good.pk).update(thumbnail='', detail='')

        call_command('backfill_image_copies', verbosity=0)

        good.refresh_from_db()
        self.assertTrue(good.thumbnail)
