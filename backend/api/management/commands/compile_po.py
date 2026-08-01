"""Compile .po files to .mo without needing GNU gettext installed.

Django reads compiled .mo catalogues at runtime, and `compilemessages` shells
out to msgfmt to produce them. That means every developer and the CI runner
would need the gettext binaries on PATH — which on Windows means an extra
install, and in CI an extra apt package, for a project with one translated
language and a few dozen strings.

The .mo format is simple enough to write directly, so this does. The parser
handles what our own catalogue uses: msgid/msgstr, adjacent string
concatenation, and comments. It is not a general gettext implementation and
does not pretend to be — plural forms and contexts would need more, and this
raises rather than guessing if it meets them.
"""

import array
import re
import struct
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

#: What every .mo starts with, little-endian.
MAGIC = 0x950412DE

_STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')


def unescape(raw):
    return (
        raw.replace('\\n', '\n')
        .replace('\\t', '\t')
        .replace('\\"', '"')
        .replace('\\\\', '\\')
    )


def parse_po(text):
    """Return {msgid: msgstr} for a catalogue.

    Entries with an empty translation are skipped: an untranslated string
    should fall through to the original, and writing "" into the catalogue
    would translate it to nothing at all.
    """
    entries = {}
    key = None
    target = None
    buffers = {'msgid': [], 'msgstr': []}

    def flush():
        msgid = ''.join(buffers['msgid'])
        msgstr = ''.join(buffers['msgstr'])
        # The empty msgid carries the header, which must be kept.
        if msgstr or msgid == '':
            entries[msgid] = msgstr
        buffers['msgid'] = []
        buffers['msgstr'] = []

    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue

        if line.startswith('msgid_plural') or line.startswith('msgctxt'):
            raise CommandError(
                f'This compiler does not handle {line.split()[0]!r}. '
                f'Install GNU gettext and use compilemessages instead.'
            )

        if line.startswith('msgid'):
            if buffers['msgid'] and target == 'msgstr':
                flush()
            key, target = 'msgid', 'msgid'
            rest = line[len('msgid') :].strip()
        elif line.startswith('msgstr'):
            target = 'msgstr'
            rest = line[len('msgstr') :].strip()
        else:
            rest = line

        if key is None:
            continue

        for match in _STRING.finditer(rest):
            buffers[target].append(unescape(match.group(1)))

    flush()
    return entries


def write_mo(entries, destination):
    """Write the minimal .mo Django needs: two sorted string tables."""
    # Sorted by msgid: the format requires it, and readers binary-search.
    items = sorted(entries.items())
    ids = b''
    strs = b''
    offsets = []

    for msgid, msgstr in items:
        encoded_id = msgid.encode('utf-8')
        encoded_str = msgstr.encode('utf-8')
        offsets.append((len(ids), len(encoded_id), len(strs), len(encoded_str)))
        ids += encoded_id + b'\x00'
        strs += encoded_str + b'\x00'

    count = len(items)
    key_start = 7 * 4 + 16 * count
    value_start = key_start + len(ids)

    key_offsets = []
    value_offsets = []
    for id_offset, id_length, str_offset, str_length in offsets:
        key_offsets += [id_length, id_offset + key_start]
        value_offsets += [str_length, str_offset + value_start]

    output = struct.pack(
        'Iiiiiii',
        MAGIC,
        0,
        count,
        7 * 4,
        7 * 4 + count * 8,
        0,  # no hash table; readers fall back to the sorted tables
        0,
    )
    output += array.array('i', key_offsets + value_offsets).tobytes()
    output += ids + strs

    destination.write_bytes(output)
    return count


class Command(BaseCommand):
    help = 'Compile locale/**/*.po into .mo, without GNU gettext.'

    def handle(self, *args, **options):
        paths = getattr(settings, 'LOCALE_PATHS', [])
        if not paths:
            raise CommandError('LOCALE_PATHS is empty; nothing to compile.')

        compiled = 0
        for root in paths:
            for po in sorted(Path(root).rglob('*.po')):
                entries = parse_po(po.read_text(encoding='utf-8'))
                written = write_mo(entries, po.with_suffix('.mo'))
                compiled += 1
                self.stdout.write(
                    f'{po.relative_to(root)}: {written} entries'
                )

        if compiled == 0:
            self.stdout.write(self.style.WARNING('No .po files found.'))
        else:
            self.stdout.write(self.style.SUCCESS(f'Compiled {compiled} file(s).'))
