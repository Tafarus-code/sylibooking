"""The API answers in the language the app asks for.

The customer app is fully translated, so an English sentence arriving from the
server is the one thing that still gives a French screen away. These assert
against real endpoints rather than the catalogue, because a message that is
translated but never reaches the caller translated is no use.
"""

from datetime import timedelta
from decimal import Decimal

from accounts.models import CustomerProfile
from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from establishments.models import Establishment, MenuItem

User = get_user_model()

#: What a French app sends. Real Flutter clients send a region too.
FRENCH = 'fr'
FRENCH_WITH_REGION = 'fr-FR,fr;q=0.9'


class LanguageTestCase(APITestCase):
    def setUp(self):
        self.lounge = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.item = MenuItem.objects.create(
            establishment=self.lounge,
            name='Menthe',
            category=MenuItem.Category.CHICHA_FLAVOR,
            price=Decimal('50000.00'),
        )

    def order_at_lounge(self, language=None):
        headers = {}
        if language:
            headers['HTTP_ACCEPT_LANGUAGE'] = language
        return self.client.post(
            reverse('order-create'),
            {
                'establishment': self.lounge.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'pickup_time': (
                    timezone.now() + timedelta(hours=2)
                ).isoformat(),
                'items': [{'menu_item': self.item.pk, 'quantity': 1}],
            },
            format='json',
            **headers,
        )


class ErrorLanguageTests(LanguageTestCase):
    def test_english_is_the_default(self):
        response = self.order_at_lounge()

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn(
            'only restaurants', str(response.data['establishment'])
        )

    def test_a_french_app_gets_french(self):
        response = self.order_at_lounge(FRENCH)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn(
            'seuls les restaurants', str(response.data['establishment'])
        )

    def test_a_region_tagged_header_still_resolves(self):
        response = self.order_at_lounge(FRENCH_WITH_REGION)

        self.assertIn(
            'seuls les restaurants', str(response.data['establishment'])
        )

    def test_the_venue_type_inside_the_sentence_is_translated_too(self):
        response = self.order_at_lounge(FRENCH)

        # "est un lounge" would be a half-translated sentence, which is worse
        # than an English one.
        self.assertIn('salon', str(response.data['establishment']))
        self.assertNotIn('lounge', str(response.data['establishment']))

    def test_a_language_we_do_not_have_falls_back_to_english(self):
        response = self.order_at_lounge('sw')

        self.assertIn(
            'only restaurants', str(response.data['establishment'])
        )

    def test_validation_messages_are_translated(self):
        response = self.client.post(
            reverse('order-create'),
            {
                'establishment': self.lounge.pk,
                'customer_name': 'Mariama',
                'customer_phone': '+224620000000',
                'pickup_time': (
                    timezone.now() - timedelta(hours=1)
                ).isoformat(),
                'items': [{'menu_item': self.item.pk, 'quantity': 1}],
            },
            format='json',
            HTTP_ACCEPT_LANGUAGE=FRENCH,
        )

        self.assertIn('à venir', str(response.data['pickup_time']))


class AccountLanguageTests(LanguageTestCase):
    def test_a_taken_username_is_explained_in_french(self):
        User.objects.create_user('mariama', password='x' * 10)

        response = self.client.post(
            reverse('customer-register'),
            {'username': 'mariama', 'password': 'chicha-2026'},
            format='json',
            HTTP_ACCEPT_LANGUAGE=FRENCH,
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('déjà pris', str(response.data['username']))

    def test_the_reset_answer_is_translated(self):
        response = self.client.post(
            reverse('customer-password-reset'),
            {'identifier': 'nobody-at-all'},
            format='json',
            HTTP_ACCEPT_LANGUAGE=FRENCH,
        )

        self.assertIn('Si ce compte existe', response.data['detail'])

    def test_an_account_with_no_contact_is_explained_in_french(self):
        user = User.objects.create_user('alone', password='x' * 10)
        CustomerProfile.objects.create(user=user, phone='')

        response = self.client.post(
            reverse('customer-password-reset'),
            {'identifier': 'alone'},
            format='json',
            HTTP_ACCEPT_LANGUAGE=FRENCH,
        )

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('ni numéro', response.data['detail'])

    def test_english_still_reads_as_it_always_did(self):
        user = User.objects.create_user('alone', password='x' * 10)
        CustomerProfile.objects.create(user=user, phone='')

        response = self.client.post(
            reverse('customer-password-reset'),
            {'identifier': 'alone'},
            format='json',
        )

        # Every client that never sends the header is untouched.
        self.assertIn('no way to send', response.data['detail'])


class CatalogueTests(LanguageTestCase):
    def test_the_compiled_catalogue_is_committed_and_loadable(self):
        """The .mo has to be in the repo, or CI serves English silently.

        Nothing in the pipeline runs the compiler, deliberately — it needs no
        gettext binaries, but it does need somebody to have run it.
        """
        from pathlib import Path

        from django.conf import settings

        mo = (
            Path(settings.LOCALE_PATHS[0])
            / 'fr'
            / 'LC_MESSAGES'
            / 'django.mo'
        )
        self.assertTrue(mo.exists(), 'run: python manage.py compile_po')

    def test_the_catalogue_is_in_step_with_the_source(self):
        """A .po edited without recompiling is the silent failure here."""
        from pathlib import Path

        from django.conf import settings

        from api.management.commands.compile_po import parse_po

        root = Path(settings.LOCALE_PATHS[0]) / 'fr' / 'LC_MESSAGES'
        entries = parse_po((root / 'django.po').read_text(encoding='utf-8'))

        from django.utils import translation

        with translation.override('fr'):
            for msgid, msgstr in entries.items():
                if not msgid or '%' in msgid:
                    continue
                self.assertEqual(
                    translation.gettext(msgid),
                    msgstr,
                    f'{msgid!r} is in the .po but not in the compiled .mo',
                )
