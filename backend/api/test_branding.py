"""Branding presets: the set itself, and who may change a venue's."""

from django.contrib.auth.models import User
from django.core.exceptions import ValidationError
from django.urls import reverse
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from establishments.models import Establishment, MerchantMembership
from establishments.theme_presets import (
    DEFAULT_PRESET,
    PRESET_KEYS,
    PRESETS,
    PRESETS_BY_KEY,
    contrast_ratio,
)

#: WCAG AA for normal-size text.
MINIMUM_CONTRAST = 4.5


class PresetDefinitionTests(APITestCase):
    """The design set is fixed, so these guard it changing by accident."""

    def test_there_are_five_presets(self):
        self.assertEqual(len(PRESETS), 5)

    def test_the_expected_presets_are_present(self):
        self.assertEqual(
            PRESET_KEYS,
            ['ember', 'palm_night', 'harmattan', 'bissap', 'indigo_soir'],
        )

    def test_ember_is_the_default(self):
        self.assertEqual(DEFAULT_PRESET, 'ember')

    def test_every_preset_is_complete(self):
        for preset in PRESETS:
            with self.subTest(preset=preset['key']):
                for field in [
                    'key',
                    'name',
                    'display_font',
                    'body_font',
                    'accent',
                    'on_accent',
                ]:
                    self.assertTrue(preset.get(field), f'{field} is missing')

    def test_colours_are_six_digit_hex(self):
        for preset in PRESETS:
            with self.subTest(preset=preset['key']):
                for field in ['accent', 'on_accent']:
                    value = preset[field]
                    self.assertRegex(value, r'^#[0-9A-Fa-f]{6}$')

    def test_text_on_accent_passes_wcag_aa(self):
        """Recomputed, not taken on trust.

        The presets claim their on-accent colour is pre-verified; this is what
        makes that claim true rather than merely asserted.
        """
        for preset in PRESETS:
            with self.subTest(preset=preset['key']):
                ratio = contrast_ratio(preset['on_accent'], preset['accent'])
                self.assertGreaterEqual(
                    ratio,
                    MINIMUM_CONTRAST,
                    f'{preset["name"]}: {ratio:.2f}:1 is below AA',
                )

    def test_the_contrast_helper_agrees_with_known_values(self):
        """Black on white is 21:1; a colour against itself is 1:1."""
        self.assertAlmostEqual(
            contrast_ratio('#000000', '#FFFFFF'), 21.0, places=1
        )
        self.assertAlmostEqual(
            contrast_ratio('#B4551C', '#B4551C'), 1.0, places=3
        )

    def test_keys_are_unique(self):
        self.assertEqual(len(PRESET_KEYS), len(set(PRESET_KEYS)))


class ThemePresetsEndpointTests(APITestCase):
    def test_the_catalogue_is_public(self):
        response = self.client.get(reverse('theme-presets'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['results']), 5)
        self.assertEqual(response.data['default'], 'ember')

    def test_it_carries_everything_the_app_needs_to_render_a_swatch(self):
        row = self.client.get(reverse('theme-presets')).data['results'][0]

        for field in ['key', 'name', 'display_font', 'body_font', 'accent']:
            self.assertIn(field, row)


class ThemePresetFieldTests(APITestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )

    def test_a_new_establishment_gets_the_default(self):
        self.assertEqual(self.establishment.theme_preset, DEFAULT_PRESET)

    def test_every_valid_key_is_accepted_by_the_model(self):
        for key in PRESET_KEYS:
            with self.subTest(preset=key):
                self.establishment.theme_preset = key
                self.establishment.full_clean()

    def test_an_unknown_key_is_rejected_by_the_model(self):
        self.establishment.theme_preset = 'neon_disco'

        with self.assertRaises(ValidationError):
            self.establishment.full_clean()

    def test_a_raw_colour_is_not_a_preset(self):
        """The point of the preset system: no free-form colour."""
        self.establishment.theme_preset = '#FF00FF'

        with self.assertRaises(ValidationError):
            self.establishment.full_clean()

    def test_a_font_name_is_not_a_preset(self):
        self.establishment.theme_preset = 'Comic Sans MS'

        with self.assertRaises(ValidationError):
            self.establishment.full_clean()


class BrandingUpdateTests(APITestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
        )
        self.other = Establishment.objects.create(
            name='Chez Fatou',
            type=Establishment.Type.RESTAURANT,
            city='Labé',
            address='Centre-ville',
        )
        self.owner = self.member('amadou', MerchantMembership.Role.OWNER)
        self.manager = self.member('ibrahima', MerchantMembership.Role.MANAGER)
        self.floor = self.member('aissatou', MerchantMembership.Role.STAFF)
        self.outsider = User.objects.create_user(
            'outsider', password='pw-for-tests'
        )

    def member(self, username, role):
        user = User.objects.create_user(username, password='pw-for-tests')
        MerchantMembership.objects.create(
            user=user, establishment=self.establishment, role=role
        )
        return user

    def authenticate(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def url(self, establishment=None):
        return reverse(
            'merchant-establishment-profile',
            args=[(establishment or self.establishment).pk],
        )

    def set_preset(self, key, establishment=None):
        return self.client.patch(
            self.url(establishment), {'theme_preset': key}, format='json'
        )

    def test_an_owner_can_change_the_preset(self):
        self.authenticate(self.owner)

        response = self.set_preset('bissap')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.establishment.refresh_from_db()
        self.assertEqual(self.establishment.theme_preset, 'bissap')

    def test_a_manager_can_too(self):
        self.authenticate(self.manager)

        self.assertEqual(
            self.set_preset('indigo_soir').status_code, status.HTTP_200_OK
        )

    def test_staff_cannot_even_by_direct_api_call(self):
        """Branding is profile editing, same ownership check as the rest."""
        self.authenticate(self.floor)

        response = self.set_preset('bissap')

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.establishment.refresh_from_db()
        self.assertEqual(self.establishment.theme_preset, DEFAULT_PRESET)

    def test_a_non_member_cannot(self):
        self.authenticate(self.outsider)

        response = self.set_preset('bissap')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_an_owner_of_one_venue_cannot_rebrand_another(self):
        self.authenticate(self.owner)

        response = self.set_preset('bissap', establishment=self.other)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.other.refresh_from_db()
        self.assertEqual(self.other.theme_preset, DEFAULT_PRESET)

    def test_every_valid_preset_is_accepted_over_the_api(self):
        self.authenticate(self.owner)

        for key in PRESET_KEYS:
            with self.subTest(preset=key):
                self.assertEqual(
                    self.set_preset(key).status_code, status.HTTP_200_OK
                )

    def test_an_unknown_preset_is_rejected(self):
        self.authenticate(self.owner)

        response = self.set_preset('neon_disco')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('theme_preset', response.data)

    def test_a_hex_colour_is_rejected(self):
        self.authenticate(self.owner)

        self.assertEqual(
            self.set_preset('#FF00FF').status_code,
            status.HTTP_400_BAD_REQUEST,
        )

    def test_a_font_name_is_rejected(self):
        self.authenticate(self.owner)

        self.assertEqual(
            self.set_preset('Comic Sans MS').status_code,
            status.HTTP_400_BAD_REQUEST,
        )

    def test_an_empty_preset_is_rejected(self):
        self.authenticate(self.owner)

        self.assertEqual(
            self.set_preset('').status_code, status.HTTP_400_BAD_REQUEST
        )


class PresetVisibleToCustomersTests(APITestCase):
    def setUp(self):
        self.establishment = Establishment.objects.create(
            name='Le Petit Baobab',
            type=Establishment.Type.LOUNGE,
            city='Conakry',
            address='Kaloum',
            theme_preset='bissap',
        )

    def test_the_detail_endpoint_reports_the_preset(self):
        response = self.client.get(
            reverse('establishment-detail', args=[self.establishment.pk])
        )

        self.assertEqual(response.data['theme_preset'], 'bissap')

    def test_the_list_endpoint_reports_it_too(self):
        row = self.client.get(reverse('establishment-list')).data['results'][0]

        self.assertEqual(row['theme_preset'], 'bissap')

    def test_only_the_key_is_sent_never_colours(self):
        """Colours live in the shared design file, not in API responses."""
        data = self.client.get(
            reverse('establishment-detail', args=[self.establishment.pk])
        ).data

        self.assertIn('theme_preset', data)
        for leaked in ['accent', 'accent_color', 'display_font', 'body_font']:
            self.assertNotIn(leaked, data)

    def test_the_key_resolves_to_a_known_preset(self):
        data = self.client.get(
            reverse('establishment-detail', args=[self.establishment.pk])
        ).data

        self.assertIn(data['theme_preset'], PRESETS_BY_KEY)
