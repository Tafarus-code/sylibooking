"""Close out bookings nobody turned up for.

A booking whose grace period has passed with no arrival is dead: the guests
are not coming, and until something says so the slot stays held and the
venue's history says the table is still sitting.

Each booking is judged against its *own* captured window, not the venue's
current one. Someone who booked when the venue held tables for ninety minutes
is judged on ninety minutes even if the venue has since moved to thirty — they
were told ninety, and that is what they agreed to.

Run by hand for now; it moves onto the scheduler in Slice 7. Written to be
safe to run as often as you like, because that is what a scheduler will do.
"""

from django.core.management.base import BaseCommand
from django.utils import timezone

from reservations.models import Reservation


def lapsed_reservations(now=None):
    """Open bookings whose own grace period has passed with no arrival.

    Bookings taken before the window was recorded have nothing to be judged
    against, so they are left alone rather than measured against today's
    rules.

    The deadline varies per row, and adding a column of minutes to a column of
    timestamps is not portable between SQLite and PostgreSQL. So the database
    narrows to open, unarrived bookings whose time has already passed — every
    lapsed booking is necessarily in that set — and the per-row comparison
    happens here. The set stays small as long as this runs regularly, which is
    the point of running it regularly.
    """
    now = now or timezone.now()

    candidates = Reservation.objects.filter(
        status__in=Reservation.OPEN_STATUSES,
        arrived_at__isnull=True,
        no_show_after_minutes__isnull=False,
        datetime__lt=now,
    )
    return [
        reservation
        for reservation in candidates
        if reservation.no_show_deadline < now
    ]


class Command(BaseCommand):
    help = 'Mark bookings nobody arrived for as missed.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='List what would be marked without writing anything.',
        )

    def handle(self, *args, **options):
        lapsed = lapsed_reservations()

        if not lapsed:
            self.stdout.write('Nothing to lapse.')
            return

        for reservation in lapsed:
            self.stdout.write(
                f'{reservation.reference} — {reservation.customer_name} '
                f'@ {reservation.datetime:%Y-%m-%d %H:%M} '
                f'({reservation.no_show_after_minutes} min grace)'
            )

        if options['dry_run']:
            self.stdout.write(
                self.style.WARNING(f'{len(lapsed)} would be marked missed.')
            )
            return

        updated = Reservation.objects.filter(
            pk__in=[r.pk for r in lapsed]
        ).update(status=Reservation.Status.NO_SHOW)

        # Imported here rather than at module scope: payments imports
        # reservations, and this command is the only thing in reservations
        # that needs to reach back the other way.
        from payments.services import settle_deposit

        forfeited = 0
        for reservation in lapsed:
            reservation.refresh_from_db()
            payment = settle_deposit(reservation)
            if payment is not None and payment.outcome == 'forfeited':
                forfeited += 1

        self.stdout.write(self.style.SUCCESS(f'{updated} marked missed.'))
        if forfeited:
            self.stdout.write(
                self.style.SUCCESS(f'{forfeited} deposit(s) kept.')
            )
