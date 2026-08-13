"""Build the small copies for pictures uploaded before they existed.

New uploads get their copies on save. Everything already in the database
predates that, and until this runs those rows serve the original to every
browse card — which is the cost this whole change was made to remove.

Idempotent, and safe to stop halfway: a row that already has its copies is
skipped, so running it twice does nothing the second time and an interrupted
run picks up where it left off. `--force` rebuilds regardless, for when the
sizes themselves change.

Deliberately not a migration. It reads and rewrites every image file in
storage, which on a real bucket is minutes of network work — a migration that
slow blocks a deploy, and one that touches object storage cannot be rolled
back by reversing it.
"""

from django.core.management.base import BaseCommand
from django.db.models import Q

from establishments.images import build_derivatives, cap_original
from establishments.models import MenuItem, Photo


class Command(BaseCommand):
    help = 'Generate thumbnail and detail copies for existing images.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--force',
            action='store_true',
            help='Rebuild copies that already exist.',
        )
        parser.add_argument(
            '--cap-originals',
            action='store_true',
            help=(
                'Also shrink oversized originals in place. Rewrites files in '
                'storage, so it is opt-in.'
            ),
        )

    def handle(self, *args, **options):
        force = options['force']
        cap = options['cap_originals']

        for model, label in ((Photo, 'photos'), (MenuItem, 'menu items')):
            rows = model.objects.exclude(image='').exclude(image=None)
            if not force:
                # Only rows missing at least one copy. A picture too small to
                # need either is looked at once per run and skipped again,
                # which is cheap and keeps the query honest.
                rows = rows.filter(
                    Q(thumbnail='')
                    | Q(thumbnail=None)
                    | Q(detail='')
                    | Q(detail=None)
                )

            done = skipped = failed = 0
            for row in rows.iterator():
                try:
                    if cap:
                        cap_original(row)
                    written = build_derivatives(row, force=force)
                except Exception as error:  # noqa: BLE001
                    # One unreadable file must not stop the run: the rest of
                    # the catalogue still wants its copies.
                    failed += 1
                    self.stderr.write(
                        self.style.WARNING(
                            f'  {label} #{row.pk}: {error}'
                        )
                    )
                    continue

                if written:
                    # Model.save() would rebuild what was just built.
                    type(row).objects.filter(pk=row.pk).update(
                        **{field: getattr(row, field).name for field in written}
                    )
                    done += 1
                else:
                    skipped += 1

            self.stdout.write(
                f'{label:12} {done} built, {skipped} already sized or too '
                f'small, {failed} unreadable'
            )

        self.stdout.write(self.style.SUCCESS('Done.'))
