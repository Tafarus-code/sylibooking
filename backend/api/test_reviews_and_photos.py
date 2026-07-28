"""Reviews and photos: who may post, and what the public sees."""

import io
import shutil
import tempfile
import uuid
from datetime import datetime, time, timedelta

from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from PIL import Image
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, Photo, Review, Space
from reservations.models import Reservation


def make_image(name='photo.jpg', fmt='JPEG', size=(40, 40)):
    """A real image file, so ImageField's own validation is exercised."""
    buffer = io.BytesIO()
    Image.new('RGB', size, color='red').save(buffer, format=fmt)
    buffer.seek(0)
    content_type = 'image/png' if fmt == 'PNG' else 'image/jpeg'
    return SimpleUploadedFile(name, buffer.read(), content_type=content_type)


class MediaRootMixin:
    """Uploads land in a temp directory, not in the project's media folder."""

    @classmethod
    def setUpClass(cls):
        cls._media_root = tempfile.mkdtemp(prefix='sylibooking-test-media-')
        cls._media_override = override_settings(MEDIA_ROOT=cls._media_root)
        cls._media_override.enable()
        super().setUpClass()

    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        cls._media_override.disable()
        shutil.rmtree(cls._media_root, ignore_errors=True)


class ReviewsTestBase(MediaRootMixin, APITestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum, Conakry',
        )
        self.other = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre-ville',
        )
        self.space = Space.objects.create(
            establishment=self.establishment, name='Table 4', capacity=4
        )
        self.other_space = Space.objects.create(
            establishment=self.other, name='Table 1', capacity=2
        )

    def make_reservation(
        self, status_=Reservation.Status.COMPLETED, space=None, name='Mariama Diallo'
    ):
        day = (timezone.localtime() - timedelta(days=2)).date()
        return Reservation.objects.create(
            space=space or self.space,
            customer_name=name,
            customer_phone='+224 620 00 00 00',
            datetime=timezone.make_aware(datetime.combine(day, time(20))),
            party_size=2,
            status=status_,
        )

    def reviews_url(self, establishment=None):
        return reverse(
            'establishment-reviews', args=[(establishment or self.establishment).pk]
        )

    def photos_url(self, establishment=None):
        return reverse(
            'establishment-photos', args=[(establishment or self.establishment).pk]
        )

    def post_review(self, reservation, rating=5, comment='Great night.'):
        return self.client.post(
            self.reviews_url(),
            {
                'reservation_reference': str(reservation.reference),
                'rating': rating,
                'comment': comment,
            },
            format='json',
        )


class PostingAReviewTests(ReviewsTestBase):
    def test_a_completed_visit_can_be_reviewed(self):
        reservation = self.make_reservation()

        response = self.post_review(reservation)

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Review.objects.count(), 1)
        self.assertEqual(response.data['rating'], 5)

    def test_a_pending_booking_cannot_be_reviewed(self):
        reservation = self.make_reservation(Reservation.Status.PENDING)

        response = self.post_review(reservation)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('reservation_reference', response.data)
        self.assertIn('complete', str(response.data).lower())
        self.assertEqual(Review.objects.count(), 0)

    def test_a_confirmed_but_unvisited_booking_cannot_be_reviewed(self):
        """Confirmed is not the same as been there."""
        reservation = self.make_reservation(Reservation.Status.CONFIRMED)

        response = self.post_review(reservation)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Review.objects.count(), 0)

    def test_a_cancelled_booking_cannot_be_reviewed(self):
        reservation = self.make_reservation(Reservation.Status.CANCELLED)

        response = self.post_review(reservation)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_reference_that_matches_nothing_is_rejected(self):
        response = self.client.post(
            self.reviews_url(),
            {
                'reservation_reference': str(uuid.uuid4()),
                'rating': 5,
                'comment': 'Never been.',
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Review.objects.count(), 0)

    def test_a_visit_to_another_venue_cannot_review_this_one(self):
        elsewhere = self.make_reservation(space=self.other_space)

        response = self.post_review(elsewhere)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Review.objects.count(), 0)

    def test_a_wrong_venue_reads_the_same_as_an_unknown_reference(self):
        """Otherwise the error is an oracle for probing valid references."""
        elsewhere = self.make_reservation(space=self.other_space)

        wrong_venue = self.post_review(elsewhere)
        unknown = self.client.post(
            self.reviews_url(),
            {'reservation_reference': str(uuid.uuid4()), 'rating': 5},
            format='json',
        )

        self.assertEqual(
            wrong_venue.data['reservation_reference'],
            unknown.data['reservation_reference'],
        )

    def test_the_same_visit_cannot_be_reviewed_twice(self):
        reservation = self.make_reservation()
        self.assertEqual(
            self.post_review(reservation).status_code, status.HTTP_201_CREATED
        )

        second = self.post_review(reservation, rating=1, comment='Changed my mind.')

        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('already been reviewed', str(second.data))
        self.assertEqual(Review.objects.count(), 1)

    def test_a_regular_can_review_each_separate_visit(self):
        """One review per booking, not one per customer."""
        first = self.make_reservation()
        second = self.make_reservation()

        self.assertEqual(
            self.post_review(first).status_code, status.HTTP_201_CREATED
        )
        self.assertEqual(
            self.post_review(second, rating=4).status_code,
            status.HTTP_201_CREATED,
        )
        self.assertEqual(Review.objects.count(), 2)

    def test_a_rating_below_one_is_rejected(self):
        response = self.post_review(self.make_reservation(), rating=0)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('rating', response.data)

    def test_a_rating_above_five_is_rejected(self):
        response = self.post_review(self.make_reservation(), rating=6)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('rating', response.data)

    def test_the_comment_is_optional(self):
        response = self.client.post(
            self.reviews_url(),
            {
                'reservation_reference': str(self.make_reservation().reference),
                'rating': 4,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['comment'], '')

    def test_new_reviews_are_visible_by_default(self):
        self.post_review(self.make_reservation())
        self.assertFalse(Review.objects.get().is_hidden)


class ReadingReviewsTests(ReviewsTestBase):
    def add_review(self, rating, hidden=False, comment='', name='Mariama Diallo'):
        return Review.objects.create(
            establishment=self.establishment,
            reservation=self.make_reservation(name=name),
            rating=rating,
            comment=comment,
            is_hidden=hidden,
        )

    def test_reviews_are_listed_newest_first(self):
        self.add_review(3, comment='First')
        self.add_review(5, comment='Second')

        response = self.client.get(self.reviews_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            [row['comment'] for row in response.data['results']],
            ['Second', 'First'],
        )

    def test_hidden_reviews_are_excluded(self):
        self.add_review(5, comment='Visible')
        self.add_review(1, hidden=True, comment='Hidden abuse')

        response = self.client.get(self.reviews_url())

        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['comment'], 'Visible')

    def test_the_response_is_paginated(self):
        for _ in range(3):
            self.add_review(4)

        response = self.client.get(self.reviews_url())

        self.assertIn('count', response.data)
        self.assertIn('results', response.data)

    def test_only_the_first_name_is_published(self):
        """The booking holds a full name and a phone; a review needs neither."""
        self.add_review(5, name='Mariama Diallo')

        row = self.client.get(self.reviews_url()).data['results'][0]

        self.assertEqual(row['author'], 'Mariama')
        self.assertNotIn('customer_phone', row)
        self.assertNotIn('Diallo', str(row))

    def test_is_hidden_is_never_exposed(self):
        self.add_review(5)

        row = self.client.get(self.reviews_url()).data['results'][0]

        self.assertNotIn('is_hidden', row)

    def test_another_venues_reviews_are_not_listed(self):
        self.add_review(5, comment='Baobab')
        Review.objects.create(
            establishment=self.other,
            reservation=self.make_reservation(space=self.other_space),
            rating=1,
            comment='Fatou',
        )

        response = self.client.get(self.reviews_url())

        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['comment'], 'Baobab')

    def test_reviews_for_an_unknown_establishment_are_404(self):
        response = self.client.get(reverse('establishment-reviews', args=[9999]))
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class AverageRatingTests(ReviewsTestBase):
    def add_review(self, rating, hidden=False):
        return Review.objects.create(
            establishment=self.establishment,
            reservation=self.make_reservation(),
            rating=rating,
            is_hidden=hidden,
        )

    def detail(self):
        return self.client.get(
            reverse('establishment-detail', args=[self.establishment.pk])
        ).data

    def test_no_reviews_means_no_average(self):
        data = self.detail()

        self.assertIsNone(data['average_rating'])
        self.assertEqual(data['review_count'], 0)

    def test_a_single_review_is_its_own_average(self):
        self.add_review(4)

        data = self.detail()

        self.assertEqual(data['average_rating'], 4.0)
        self.assertEqual(data['review_count'], 1)

    def test_the_average_is_the_mean_of_the_ratings(self):
        for rating in [5, 4, 3]:
            self.add_review(rating)

        self.assertEqual(self.detail()['average_rating'], 4.0)

    def test_the_average_is_rounded_to_one_decimal(self):
        for rating in [5, 4, 4]:
            self.add_review(rating)

        # 13/3 = 4.333...
        self.assertEqual(self.detail()['average_rating'], 4.3)

    def test_hidden_reviews_do_not_count_towards_the_average(self):
        """Moderation would be pointless if a hidden 1-star still dragged it."""
        self.add_review(5)
        self.add_review(5)
        self.add_review(1, hidden=True)

        data = self.detail()

        self.assertEqual(data['average_rating'], 5.0)
        self.assertEqual(data['review_count'], 2)

    def test_hiding_every_review_returns_the_average_to_null(self):
        self.add_review(5, hidden=True)

        data = self.detail()

        self.assertIsNone(data['average_rating'])
        self.assertEqual(data['review_count'], 0)


class PhotoUploadTests(ReviewsTestBase):
    def setUp(self):
        super().setUp()
        self.staff = User.objects.create_user('amadou', password='pw-for-tests')
        self.establishment.staff.add(self.staff)

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def test_a_customer_with_a_booking_can_upload(self):
        reservation = self.make_reservation(Reservation.Status.CONFIRMED)

        response = self.client.post(
            self.photos_url(),
            {
                'reservation_reference': str(reservation.reference),
                'image': make_image(),
                'caption': 'Great terrace',
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        photo = Photo.objects.get()
        self.assertEqual(photo.uploaded_by_role, Photo.UploaderRole.CUSTOMER)
        self.assertEqual(photo.reservation, reservation)

    def test_any_booking_status_is_enough_for_a_customer_photo(self):
        """Unlike reviews: someone turned away still has something to show."""
        reservation = self.make_reservation(Reservation.Status.PENDING)

        response = self.client.post(
            self.photos_url(),
            {
                'reservation_reference': str(reservation.reference),
                'image': make_image(),
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_a_stranger_cannot_upload(self):
        response = self.client.post(
            self.photos_url(), {'image': make_image()}, format='multipart'
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Photo.objects.count(), 0)

    def test_an_unknown_reference_cannot_upload(self):
        response = self.client.post(
            self.photos_url(),
            {'reservation_reference': str(uuid.uuid4()), 'image': make_image()},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Photo.objects.count(), 0)

    def test_a_booking_at_another_venue_cannot_upload_here(self):
        elsewhere = self.make_reservation(space=self.other_space)

        response = self.client.post(
            self.photos_url(),
            {
                'reservation_reference': str(elsewhere.reference),
                'image': make_image(),
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_merchant_staff_upload_official_photos(self):
        self.authenticate(self.staff)

        response = self.client.post(
            self.photos_url(),
            {'image': make_image(), 'caption': 'Our VIP room'},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        photo = Photo.objects.get()
        self.assertEqual(photo.uploaded_by_role, Photo.UploaderRole.MERCHANT)
        self.assertIsNone(photo.reservation)

    def test_staff_of_another_venue_cannot_upload_here(self):
        outsider = User.objects.create_user('fatou', password='pw-for-tests')
        self.other.staff.add(outsider)
        self.authenticate(outsider)

        response = self.client.post(
            self.photos_url(), {'image': make_image()}, format='multipart'
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Photo.objects.count(), 0)

    def test_a_non_image_file_is_rejected(self):
        upload = SimpleUploadedFile(
            'notes.txt', b'this is not an image', content_type='text/plain'
        )

        response = self.client.post(
            self.photos_url(),
            {
                'reservation_reference': str(self.make_reservation().reference),
                'image': upload,
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('image', response.data)
        self.assertEqual(Photo.objects.count(), 0)

    def test_an_image_with_a_disallowed_extension_is_rejected(self):
        upload = make_image(name='photo.gif', fmt='PNG')

        response = self.client.post(
            self.photos_url(),
            {
                'reservation_reference': str(self.make_reservation().reference),
                'image': upload,
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Photo.objects.count(), 0)

    @override_settings(MAX_PHOTO_UPLOAD_BYTES=500)
    def test_an_oversized_image_is_rejected(self):
        big = make_image(size=(400, 400))

        response = self.client.post(
            self.photos_url(),
            {
                'reservation_reference': str(self.make_reservation().reference),
                'image': big,
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('too large', str(response.data).lower())
        self.assertEqual(Photo.objects.count(), 0)

    def test_png_is_accepted(self):
        response = self.client.post(
            self.photos_url(),
            {
                'reservation_reference': str(self.make_reservation().reference),
                'image': make_image(name='photo.png', fmt='PNG'),
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_the_uploaded_filename_is_not_kept(self):
        """It can carry a customer's name, and two IMG_0001.jpg must not clash."""
        response = self.client.post(
            self.photos_url(),
            {
                'reservation_reference': str(self.make_reservation().reference),
                'image': make_image(name='mariama-birthday.jpg'),
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertNotIn('mariama', Photo.objects.get().image.name.lower())


class ReadingPhotosTests(ReviewsTestBase):
    def add_photo(self, hidden=False, caption='', role=None):
        return Photo.objects.create(
            establishment=self.establishment,
            uploaded_by_role=role or Photo.UploaderRole.MERCHANT,
            image=make_image(),
            caption=caption,
            is_hidden=hidden,
        )

    def test_photos_are_listed(self):
        self.add_photo(caption='Terrace')

        response = self.client.get(self.photos_url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['caption'], 'Terrace')

    def test_hidden_photos_are_excluded(self):
        self.add_photo(caption='Fine')
        self.add_photo(hidden=True, caption='Reported')

        response = self.client.get(self.photos_url())

        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['caption'], 'Fine')

    def test_the_image_url_is_absolute(self):
        self.add_photo()

        row = self.client.get(self.photos_url()).data['results'][0]

        self.assertTrue(row['image'].startswith('http'))

    def test_the_uploader_role_is_reported(self):
        self.add_photo(role=Photo.UploaderRole.CUSTOMER)

        row = self.client.get(self.photos_url()).data['results'][0]

        self.assertEqual(row['uploaded_by_role'], 'customer')
        self.assertEqual(row['uploaded_by_role_display'], 'Customer')

    def test_is_hidden_is_never_exposed(self):
        self.add_photo()

        row = self.client.get(self.photos_url()).data['results'][0]

        self.assertNotIn('is_hidden', row)

    def test_the_response_is_paginated(self):
        self.add_photo()

        response = self.client.get(self.photos_url())

        self.assertIn('count', response.data)
        self.assertIn('results', response.data)
