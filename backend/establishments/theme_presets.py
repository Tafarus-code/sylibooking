"""Establishment branding presets, loaded from the shared design file.

A fixed design set rather than database rows: merchants choose a key, never a
colour or a font. Keeping them out of the database means a preset cannot be
edited into something unreadable, and the whole set can be changed in one
reviewed commit.

The file is shared with the Flutter side, which mirrors it in Dart and has a
test comparing the two, so the definitions cannot drift apart.
"""

import json
import os
from pathlib import Path

_HERE = Path(__file__).resolve().parent

#: Where the shared design file might be, in the order to look.
#:
#: Two layouts, both real. In a checkout the file sits at the repo root beside
#: `backend/`; in the container `backend/` *is* the root, so it is copied in
#: beside the app instead. Searching rather than assuming is what stopped the
#: image building at all — the path was right for a checkout and resolved to
#: `/design/theme_presets.json` inside the image.
_CANDIDATES = (
    # backend/establishments/ -> backend/ -> repo root -> design/
    _HERE.parent.parent / 'design' / 'theme_presets.json',
    # /app/establishments/ -> /app/ -> /app/design/
    _HERE.parent / 'design' / 'theme_presets.json',
)


def _find():
    override = os.environ.get('THEME_PRESETS_FILE')
    if override:
        return Path(override)
    for candidate in _CANDIDATES:
        if candidate.exists():
            return candidate
    # Named so the error says what was looked for rather than only what was
    # missing — the failure mode here is a path that is right somewhere else.
    raise FileNotFoundError(
        'theme_presets.json not found. Looked in: '
        + ', '.join(str(c) for c in _CANDIDATES)
    )


PRESETS_FILE = _find()


def _load():
    with PRESETS_FILE.open(encoding='utf-8') as handle:
        return json.load(handle)


_DATA = _load()

#: Ordered as the merchant app shows them.
PRESETS = _DATA['presets']

#: The key a new establishment gets.
DEFAULT_PRESET = _DATA['default']

PRESETS_BY_KEY = {preset['key']: preset for preset in PRESETS}

#: For the model's `choices`, in file order.
PRESET_CHOICES = [(preset['key'], preset['name']) for preset in PRESETS]

PRESET_KEYS = [preset['key'] for preset in PRESETS]

assert DEFAULT_PRESET in PRESETS_BY_KEY, (
    f'Default preset {DEFAULT_PRESET!r} is not one of the defined presets.'
)


def relative_luminance(hex_colour):
    """WCAG relative luminance for a `#RRGGBB` string."""
    value = hex_colour.lstrip('#')
    channels = [int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)]

    def linearise(channel):
        if channel <= 0.03928:
            return channel / 12.92
        return ((channel + 0.055) / 1.055) ** 2.4

    red, green, blue = (linearise(channel) for channel in channels)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast_ratio(foreground, background):
    """WCAG contrast ratio between two `#RRGGBB` strings, 1.0 to 21.0."""
    lighter = max(
        relative_luminance(foreground), relative_luminance(background)
    )
    darker = min(relative_luminance(foreground), relative_luminance(background))
    return (lighter + 0.05) / (darker + 0.05)
