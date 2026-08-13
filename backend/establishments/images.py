"""Making an uploaded photograph fit down a mobile connection.

A phone here takes a twelve-megapixel photograph and a browse list shows
twenty venues. Serving the originals means a list that crawls on the exact
network most of this market is on — and paying to move bytes nobody can see,
since the card they land in is a few hundred pixels wide.

So every upload produces two smaller copies and keeps the original:

- **card** (400px) for a list row, a menu row, the dishes feed
- **detail** (1200px), served by the API and not yet asked for by either app —
  it is here for a venue header, and because generating it later would mean
  reprocessing every photograph in the bucket a second time
- the **original**, for the full-screen viewer, which is the one place the
  photograph itself is the point

Three rules the rest of the code depends on.

Nothing is ever upscaled. A picture already smaller than a derivative would
be gets no derivative at all, and the caller falls back to the original —
which is smaller still, so the fallback is never the expensive path.

A derivative is a JPEG, always. Transparency is discarded because none of
these surfaces show any, and a PNG screenshot of a menu costs several times
what the same picture costs as a JPEG.

Failure to build a derivative is not failure to accept the upload. A photo
that Pillow cannot process still saves, still serves, and simply has no small
copy — the alternative is refusing a merchant's picture because of a codec.
"""

import logging
from io import BytesIO

from django.core.files.base import ContentFile
from PIL import Image, ImageOps, UnidentifiedImageError

logger = logging.getLogger(__name__)

#: Wide enough for a full-bleed card on a 3x phone, small enough to be cheap.
CARD_WIDTH = 400

#: A venue header, and the largest thing shown before someone asks for the
#: photograph itself.
DETAIL_WIDTH = 1200

#: What an original is allowed to be once stored. A modern phone camera is
#: several times this in each direction, and nothing in either app can show
#: it — so the extra pixels are pure transfer cost, on every later request.
MAX_STORED_WIDTH = 2000

#: Chosen by eye against the seeded photographs: below this, banding shows on
#: the flat colour fields these images tend to have.
JPEG_QUALITY = 82


def _open(source):
    """A Pillow image from a Django file, oriented the way it was shot.

    `exif_transpose` matters more than it looks: a phone writes a landscape
    sensor image plus a rotation flag, and a derivative that ignores the flag
    comes out sideways while the original looks fine.
    """
    source.open()
    try:
        image = Image.open(source)
        image.load()
    finally:
        source.close()
    return ImageOps.exif_transpose(image)


def _encode(image):
    buffer = BytesIO()
    # RGB because the target is JPEG: a palette or alpha image cannot be
    # written as one, and every surface these appear on is opaque anyway.
    if image.mode != 'RGB':
        image = image.convert('RGB')
    image.save(
        buffer,
        format='JPEG',
        quality=JPEG_QUALITY,
        optimize=True,
        progressive=True,
    )
    return buffer.getvalue()


def derivative(source, width):
    """A copy of `source` no wider than `width`, or None if it is already.

    None is the useful answer, not a failure: it tells the caller to serve the
    original, which in that case is the smaller file.
    """
    try:
        image = _open(source)
    except (UnidentifiedImageError, OSError, ValueError) as error:
        logger.warning('could not read image for resizing: %s', error)
        return None

    if image.width <= width:
        return None

    height = round(image.height * width / image.width)
    image = image.resize((width, max(1, height)), Image.LANCZOS)
    return ContentFile(_encode(image))


def capped(source):
    """The original, shrunk to [MAX_STORED_WIDTH], or None if already inside.

    Applied to what is stored rather than to what is served: an oversized
    original costs on every later read, and no screen in either app can use
    the pixels being thrown away.
    """
    return derivative(source, MAX_STORED_WIDTH)


def copy_url(instance, field, request=None):
    """The URL of one copy, falling back to the original when there is none.

    The fallback is the whole reason this is a function and not four lines
    repeated in four serializers. A derivative is missing in three ordinary
    cases — a row uploaded before this existed, a picture already too small to
    be worth shrinking, and one Pillow could not read — and in all three the
    original is the right answer. None of them is an error, and none of them
    may be a 500 on a customer's browse list.
    """
    file = getattr(instance, field, None) or instance.image
    if not file:
        return None
    return request.build_absolute_uri(file.url) if request else file.url


def cap_original(instance):
    """Shrink an oversized stored original in place. True if it was rewritten.

    In place, under the same name, rather than saving a new file: the name is
    already in the database and on other rows' URLs, and a rename would leave
    the old object behind in the bucket for nobody.

    Done at the model rather than in the upload serializer so it covers every
    way a picture arrives — the API, the admin, a management command — not
    only the one a customer uses.
    """
    if not instance.image:
        return False

    content = capped(instance.image)
    if content is None:
        return False

    storage, name = instance.image.storage, instance.image.name
    storage.delete(name)
    storage.save(name, content)
    return True


def derivative_name(original_name, suffix):
    """`menu/7/abc.png` + `card` -> `menu/7/abc-card.jpg`.

    Beside the original rather than in a folder of its own, so a venue's
    images stay together and deleting the folder takes the copies with it.
    """
    stem = original_name.rsplit('.', 1)[0]
    return f'{stem}-{suffix}.jpg'


def build_derivatives(instance, *, force=False):
    """Fill in `thumbnail` and `detail` for a model that has them.

    Returns the field names it wrote, so a caller can pass them to
    `save(update_fields=...)` and avoid a second full write.

    Idempotent by default: a row that already has its copies is left alone,
    which is what lets the backfill command run twice and the model call this
    on every save.
    """
    if not instance.image:
        return []

    written = []
    for field, width in (('thumbnail', CARD_WIDTH), ('detail', DETAIL_WIDTH)):
        if getattr(instance, field) and not force:
            continue

        content = derivative(instance.image, width)
        if content is None:
            # Already small enough. Leave the field empty and let the
            # serializer fall back to the original.
            continue

        getattr(instance, field).save(
            derivative_name(instance.image.name, field),
            content,
            save=False,
        )
        written.append(field)

    return written
