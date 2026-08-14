"""Compile .po files to .mo without needing GNU gettext installed.

Django reads compiled .mo catalogues at runtime, and `compilemessages` shells
out to msgfmt to produce them. That means every developer and the CI runner
would need the gettext binaries on PATH — which on Windows means an extra
install, and in CI an extra apt package, for a project with one translated
language and a few dozen strings.

The .mo format is simple enough to write directly, so this does. The parser
handles what our own catalogue uses: msgid/msgstr, msgctxt, adjacent string
concatenation, and comments. It is not a general gettext implementation and
does not pretend to be — plural forms would need more, and this raises rather
than guessing if it meets them.
"""

import array
import re
import struct
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

#: What every .mo starts with, little-endian.
MAGIC = 0x950412DE

#: gettext joins a context to its msgid with EOT before looking the pair up.
CONTEXT_SEPARATOR = '\x04'

_STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')


def unescape(raw):
    return (
        raw.replace('\\n', '\n')
        .replace('\\t', '\t')
        .replace('\\"', '"')
        .replace('\\\\', '\\')
    )


def parse_po(text):
    """Return {key: msgstr} for a catalogue.

    The key is the msgid, or `msgctxt \\x04 msgid` for a contextual entry —
    the same key gettext itself looks up, which is what lets "Completed" mean
    one thing for a payment and another for a kitchen ticket.

    Entries with an empty translation are skipped: an untranslated string
    should fall through to the original, and writing "" into the catalogue
    would translate it to nothing at all.
    """
    entries = {}
    started = False
    target = None
    buffers = {'msgctxt': [], 'msgid': [], 'msgstr': []}

    def flush():
        msgid = ''.join(buffers['msgid'])
        msgstr = ''.join(buffers['msgstr'])
        context = ''.join(buffers['msgctxt'])
        key = f'{context}{CONTEXT_SEPARATOR}{msgid}' if context else msgid
        # The empty msgid carries the header, which must be kept.
        if msgstr or key == '':
            entries[key] = msgstr
        for buffer in buffers.values():
            buffer.clear()

    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue

        if line.startswith('msgid_plural'):
            raise CommandError(
                "This compiler does not handle 'msgid_plural'. "
                'Install GNU gettext and use compilemessages instead.'
            )

        # msgctxt opens an entry the way a bare msgid does, so the flush has
        # to happen here too — otherwise the context lands on the entry that
        # was already finished and this one goes in without it.
        if line.startswith(('msgctxt', 'msgid')):
            keyword = 'msgctxt' if line.startswith('msgctxt') else 'msgid'
            if started and target == 'msgstr':
                flush()
            # A msgid following its own msgctxt continues the same entry.
            if not (keyword == 'msgid' and buffers['msgctxt']):
                buffers['msgctxt'].clear()
            started, target = True, keyword
            rest = line[len(keyword) :].strip()
        elif line.startswith('msgstr'):
            target = 'msgstr'
            rest = line[len('msgstr') :].strip()
        else:
            rest = line

        if not started:
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
