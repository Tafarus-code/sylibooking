"""Images on menu items, and who may attach one."""

import io
import shutil
import tempfile
from decimal import Decimal

from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import reverse
from PIL import Image
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import (
    Establishment,
    MenuItem,
    MerchantMembership,
)


def make_image(name='dish.jpg', fmt='JPEG', size=(40, 40)):
    buffer = io.BytesIO()
    Image.new('RGB', size, color='orange').save(buffer, format=fmt)
    buffer.seek(0)
    return SimpleUploadedFile(name, buffer.read(), content_type='image/jpeg')


class MenuImageTestBase(APITestCase):
    @classmethod
    def setUpClass(cls):
        cls._media_root = tempfile.mkdtemp(prefix='sylibooking-menu-media-')
        cls._media_override = override_settings(MEDIA_ROOT=cls._media_root)
        cls._media_override.enable()
        super().setUpClass()

    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        cls._media_override.disable()
        shutil.rmtree(cls._media_root, ignore_errors=True)

    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.owner = self.member('amadou', MerchantMembership.Role.OWNER)
        self.floor = self.member('aissatou', MerchantMembership.Role.STAFF)

    def member(self, username, role):
        user = User.objects.create_user(username, password='pw-for-tests')
        MerchantMembership.objects.create(
            user=user, establishment=self.establishment, role=role
        )
        return user

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def menu_url(self):
        return reverse('merchant-menu', args=[self.establishment.pk])

    def item_url(self, item):
        return reverse(
            'merchant-menu-item', args=[self.establishment.pk, item.pk]
        )

    def add_item(self, with_image=False):
        return MenuItem.objects.create(
            establishment=self.establishment,
            name='Poulet braisé',
            category=MenuItem.Category.FOOD,
            price=Decimal('75000'),
            image=make_image() if with_image else None,
        )


class AttachingAnImageTests(MenuImageTestBase):
    def test_an_owner_can_create_an_item_with_an_image(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.menu_url(),
            {
                'name': 'Brochettes',
                'category': 'food',
                'price': '50000',
                'image': make_image(),
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(MenuItem.objects.get().image)
        self.assertIsNotNone(response.data['image_url'])

    def test_an_image_is_optional(self):
        """Most items will never have one, and a slow connection must not
        stop a merchant adding a dish."""
        self.authenticate(self.owner)

        response = self.client.post(
            self.menu_url(),
            {'name': 'Brochettes', 'category': 'food', 'price': '50000'},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertFalse(MenuItem.objects.get().image)
        self.assertIsNone(response.data['image_url'])

    def test_an_image_can_be_added_to_an_existing_item(self):
        item = self.add_item()
        self.authenticate(self.owner)

        response = self.client.patch(
            self.item_url(item), {'image': make_image()}, format='multipart'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        item.refresh_from_db()
        self.assertTrue(item.image)

    def test_staff_cannot_attach_an_image(self):
        """Images are menu editing, which staff do not have."""
        item = self.add_item()
        self.authenticate(self.floor)

        response = self.client.patch(
            self.item_url(item), {'image': make_image()}, format='multipart'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        item.refresh_from_db()
        self.assertFalse(item.image)

    def test_a_non_image_file_is_rejected(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.menu_url(),
            {
                'name': 'Brochettes',
                'category': 'food',
                'price': '50000',
                'image': SimpleUploadedFile(
                    'notes.txt', b'not an image', content_type='text/plain'
                ),
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(MenuItem.objects.count(), 0)

    @override_settings(MAX_PHOTO_UPLOAD_BYTES=500)
    def test_an_oversized_image_is_rejected(self):
        self.authenticate(self.owner)

        response = self.client.post(
            self.menu_url(),
            {
                'name': 'Brochettes',
                'category': 'food',
                'price': '50000',
                'image': make_image(size=(400, 400)),
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('too large', str(response.data).lower())

    def test_the_uploaded_filename_is_not_kept(self):
        self.authenticate(self.owner)

        self.client.post(
            self.menu_url(),
            {
                'name': 'Brochettes',
                'category': 'food',
                'price': '50000',
                'image': make_image(name='amadou-kitchen.jpg'),
            },
            format='multipart',
        )

        self.assertNotIn('amadou', MenuItem.objects.get().image.name.lower())

    def test_menu_images_land_in_their_own_folder(self):
        """Not mixed in with venue photos."""
        self.authenticate(self.owner)

        self.client.post(
            self.menu_url(),
            {
                'name': 'Brochettes',
                'category': 'food',
                'price': '50000',
                'image': make_image(),
            },
            format='multipart',
        )

        self.assertTrue(MenuItem.objects.get().image.name.startswith('menu/'))


class ImageVisibleToCustomersTests(MenuImageTestBase):
    def detail(self):
        return self.client.get(
            reverse('establishment-detail', args=[self.establishment.pk])
        ).data

    def test_an_item_with_an_image_exposes_an_absolute_url(self):
        self.add_item(with_image=True)

        item = self.detail()['menu'][0]['items'][0]

        self.assertIsNotNone(item['image'])
        self.assertTrue(item['image'].startswith('http'))

    def test_an_item_without_an_image_reports_null(self):
        self.add_item()

        item = self.detail()['menu'][0]['items'][0]

        self.assertIsNone(item['image'])

    def test_an_unavailable_item_is_still_excluded_even_with_an_image(self):
        item = self.add_item(with_image=True)
        item.is_available = False
        item.save(update_fields=['is_available'])

        self.assertEqual(self.detail()['menu'], [])
