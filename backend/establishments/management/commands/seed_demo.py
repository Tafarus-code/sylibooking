"""Fill a development database with enough of a city to actually test against.

Twenty venues across Conakry and Labé, each with its own menu, hours, spaces,
branding, photographs, bookings, orders and reviews. The point is variety: a
single seeded venue proves a screen renders, while twenty prove the list
sorts, the filters filter, the branding does not bleed and the empty states
are genuinely rare.

Additive and idempotent. A venue whose name already exists is left alone, so
running this twice is safe and it will never touch data you created by hand.
Nothing here deletes anything.
"""

import random
from datetime import datetime, time, timedelta
from decimal import Decimal
from io import BytesIO

from accounts.models import CustomerProfile
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone
from orders.models import Order, OrderItem
from PIL import Image, ImageDraw

from establishments.favourites import Favourite
from establishments.models import (
    Establishment,
    MenuItem,
    MerchantMembership,
    OpeningHours,
    Photo,
    Review,
    Space,
)
from payments.models import Payment
from reservations.models import Reservation
from reservations.no_show import no_show_window

User = get_user_model()

#: Fixed seed, so a demo looks the same twice running and a bug found on one
#: machine can be reproduced on another.
SEED = 20260731

# Real neighbourhoods, with coordinates close enough that distance sorting and
# "Get directions" have something honest to work with.
CONAKRY = [
    ('Kaloum', 9.5092, -13.7122),
    ('Dixinn', 9.5370, -13.6780),
    ('Ratoma', 9.5820, -13.6420),
    ('Matam', 9.5250, -13.6650),
    ('Matoto', 9.5700, -13.5900),
    ('Kipé', 9.6050, -13.6280),
    ('Lambanyi', 9.6300, -13.6100),
]
LABE = [('Labé Centre', 11.3180, -12.2830), ('Daka', 11.3260, -12.2950)]

RESTAURANTS = [
    ('Le Damier', 'Cuisine guinéenne et grillades au feu de bois'),
    ('Chez Mariama', "Riz gras, sauce feuille, et l'accueil de la maison"),
    ('Le Baobab Doré', 'Poissons braisés du port de Boulbinet'),
    ('Terrasse du Niger', 'Grillades et jus frais en terrasse'),
    ('Maquis Kaloum', 'Le maquis de midi, rapide et copieux'),
    ('La Paillote', 'Poulet yassa, attiéké, et bissap maison'),
    ('Saveurs du Fouta', 'Spécialités peules et plats du Fouta-Djalon'),
    ('Le Petit Marché', 'Cuisine du marché, ce qui est frais ce jour-là'),
    ('Riz & Sauce', "Le plat du jour, du lundi au samedi"),
    ('Chez Sory', 'Brochettes, alloco et ambiance de quartier'),
    ('Le Wharf', 'Fruits de mer face à la mer'),
]

LOUNGES = [
    ('Le Petit Baobab', 'Chicha, musique douce, et la nuit devant soi'),
    ('Sky Lounge Kipé', 'Rooftop, chicha premium, coucher de soleil'),
    ('Le Nimba', 'Salon privé et terrasse, ouvert tard'),
    ('Villa 224', 'Chicha et cocktails, entre amis'),
    ('Le Cocotier', 'Jardin, narguilé, et de la place pour parler'),
    ('Bissap Lounge', 'Ambiance calme, bissap glacé, chicha maison'),
    ('La Terrasse Dixinn', 'La terrasse qui ne ferme pas avant deux heures'),
    ('Nuit Blanche', 'Le salon des fins de semaine'),
    ('Le Salon Rouge', 'Feutré, discret, chicha au charbon naturel'),
    ('Kaloum Nights', 'Vue sur la baie, chicha et musique live'),
    ('Le Hangar', 'Grand espace, groupes bienvenus'),
]

FOOD = [
    ('Poulet yassa', 'Poulet mariné aux oignons et citron, riz blanc', 75000),
    ('Poisson braisé', 'Capitaine entier, sauce tomate, attiéké', 90000),
    ('Riz gras', 'Riz au gras, viande de bœuf, légumes', 45000),
    ('Sauce feuille', 'Feuilles de patate, viande fumée, riz', 50000),
    ('Brochettes de bœuf', 'Trois brochettes, oignons, piment', 40000),
    ('Alloco', 'Bananes plantains frites, sauce piquante', 20000),
    ('Attiéké poisson', 'Semoule de manioc et poisson grillé', 65000),
    ('Mafé', "Sauce d'arachide, viande, riz blanc", 55000),
    ('Fouti', 'Riz au poisson, à la guinéenne', 60000),
    ('Poulet braisé', 'Demi-poulet braisé, frites', 80000),
    ('Soupe kandia', 'Gombo, huile de palme, poisson fumé', 55000),
]

DRINKS = [
    ('Jus de bissap', "Hibiscus glacé, peu sucré", 15000),
    ('Jus de gingembre', 'Gingembre frais, citron', 15000),
    ('Jus de baobab', 'Pain de singe, lait, glace', 18000),
    ("Eau minérale", '1,5 litre', 8000),
    ('Coca-Cola', 'Bouteille 33cl', 10000),
    ('Café touba', 'Café au poivre de Guinée', 12000),
    ('Thé à la menthe', 'Servi en trois verres', 14000),
]

CHICHA = [
    ('Menthe glaciale', 'La classique, fraîche et longue', 50000),
    ('Double pomme', 'Pomme rouge et pomme verte', 50000),
    ('Raisin menthe', 'Doux, pour les longues soirées', 55000),
    ('Pastèque', "Léger, l'été toute l'année", 55000),
    ('Citron basilic', 'Acidulé, un peu herbacé', 60000),
    ('Mangue', 'Sucré, très demandé', 55000),
    ('Blue mist', 'Myrtille et menthe', 60000),
]

FIRST_NAMES = [
    'Mariama', 'Ibrahima', 'Aïssatou', 'Mamadou', 'Fatoumata', 'Alpha',
    'Kadiatou', 'Ousmane', 'Hadja', 'Sékou', 'Binta', 'Thierno',
    'Aminata', 'Lansana', 'Néné', 'Abdoulaye',
]
SURNAMES = [
    'Diallo', 'Barry', 'Bah', 'Sow', 'Camara', 'Touré', 'Condé', 'Keita',
    'Sylla', 'Baldé', 'Soumah', 'Doumbouya',
]

# Customer accounts, one per contact-details case. An account is optional in
# this product, so what varies between these is not the bookings — it is what
# the account could be recovered with, which is the thing the profile screen
# talks about and the only way to see all of its states without editing rows by
# hand.
CUSTOMERS = [
    ('mariama', 'Mariama', 'Diallo', '+224620111222', 'mariama.diallo@example.gn'),
    ('sekou', 'Sékou', 'Camara', '+224621333444', ''),
    ('kadiatou', 'Kadiatou', 'Barry', '', 'kadiatou.barry@example.gn'),
    # Neither, deliberately: this is the account the app warns would be lost
    # if the password went with the phone.
    ('binta', 'Binta', 'Sow', '', ''),
]

REVIEW_LINES = [
    ('Excellent accueil, on reviendra.', 5),
    ("Le poisson était parfait, service un peu lent mais ça valait l'attente.", 4),
    ('Bonne ambiance, chicha bien préparée.', 5),
    ('Correct sans plus. Les prix ont augmenté.', 3),
    ('Terrasse agréable, musique un peu forte.', 4),
    ('Rapide le midi, parfait pour la pause.', 5),
    ("Portion généreuse, j'ai partagé et c'était assez pour deux.", 5),
    ('Réservation bien prise en compte, table prête à l’heure.', 5),
    ("J'ai attendu vingt minutes pour la commande.", 3),
    ('Le meilleur yassa de Conakry, sans exagérer.', 5),
]

PRESETS = ['ember', 'palm_night', 'harmattan', 'bissap', 'indigo_soir']

# --- The long history -------------------------------------------------------
#
# Everything below shapes `--months` of trading. The near-term seeding further
# down fills today and the week either side, which proves a list renders. It
# proves nothing about the screens that look backwards: insights offers a
# 90-day window, and the payments dashboard and CSV export take arbitrary date
# ranges. Against six weeks of thin data all three draw a half-empty chart,
# which reads as a broken screen rather than a quiet month.

#: How busy each weekday is against an average one, Monday first. A Friday is
#: not a Tuesday, and "which nights are worth opening for" — the question the
#: insights screen exists to answer — has no answer in uniform data.
WEEKDAY_WEIGHT = [0.55, 0.6, 0.75, 0.95, 1.5, 1.6, 1.05]

#: Bookings per venue on an average day, before weekday, popularity and trend.
BASE_COVERS_PER_DAY = 3.0

#: What became of a booking whose time has passed.
#:
#: NO_SHOW is in here because the insights screen reports a no-show rate and
#: the seed has never produced one — so the single number the grace-period
#: settings exist to move has always been null. A venue that never loses a
#: table is not a venue.
PAST_OUTCOMES = [
    (Reservation.Status.COMPLETED, 78),
    (Reservation.Status.CANCELLED, 14),
    (Reservation.Status.NO_SHOW, 8),
]

#: Faces that come back. Returning customers are counted by phone number, so a
#: history of strangers reports every venue as having no regulars — which is
#: false, and looks like a metric that does not work.
REGULARS_PER_VENUE = 22

#: How often a booking is made by somebody the venue has served before.
REGULAR_SHARE = 0.62

#: Orders per restaurant on an average day, before the same shaping.
BASE_ORDERS_PER_DAY = 2.5

ORDER_OUTCOMES = [(Order.Status.COMPLETED, 88), (Order.Status.CANCELLED, 12)]

#: Service hours bookings actually land in, by venue type. Weighted by
#: repetition rather than by a distribution, because the shape wanted here is
#: "two services with peaks", which a flat random hour does not give.
SERVICE_HOURS = {
    True: [18, 19, 20, 20, 21, 21, 21, 22, 22, 23],   # lounge
    False: [12, 12, 13, 13, 14, 19, 19, 20, 20, 21],  # kitchen
}

#: Bookings per venue per month above which a window counts as already
#: seeded. Comfortably above what the near-term seeding leaves behind (a
#: dozen or so in total) and comfortably below what a month of history writes
#: (fifty at the quietest venue), so the two are never confused.
SEEDED_PER_MONTH = 25

#: Rows written per database round trip. Six months across twenty-two venues is
#: tens of thousands of rows; one INSERT each turns a seed into a coffee break.
BATCH = 500


def swatch(name, width=1200, height=800, seed=0):
    """A generated placeholder image.

    Deliberately abstract rather than a stock photograph: seeded data should
    look like seeded data, so nobody mistakes a demo venue for a real one or
    ships a stranger's photograph by accident.
    """
    rng = random.Random(f'{name}-{seed}')
    hue = rng.randint(0, 255)
    base = (hue, (hue * 3) % 200 + 30, (hue * 7) % 180 + 40)

    image = Image.new('RGB', (width, height), base)
    draw = ImageDraw.Draw(image)

    # A few translucent bands, so thumbnails are distinguishable at a glance.
    for i in range(6):
        y = int(height * i / 6)
        shade = tuple(min(255, c + rng.randint(-40, 60)) for c in base)
        draw.rectangle([0, y, width, y + height // 6], fill=shade)

    draw.rectangle([0, height - 140, width, height], fill=(16, 35, 27))
    draw.text((40, height - 100), name[:40], fill=(247, 243, 236))

    buffer = BytesIO()
    image.save(buffer, format='JPEG', quality=70)
    return ContentFile(buffer.getvalue(), name=f'{abs(hash(name))}.jpg')


class Command(BaseCommand):
    help = 'Fill a development database with a city worth of demo data.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--password',
            default='sylibooking',
            help='Password for every seeded merchant account.',
        )
        parser.add_argument(
            '--months',
            type=int,
            default=6,
            help=(
                'Months of trading history to generate behind today. '
                'Default 6, which covers the longest insights window (90 '
                'days) twice over and gives the dashboard and CSV export a '
                'real range to be asked for. 0 skips it.'
            ),
        )

    def handle(self, *args, **options):
        self.rng = random.Random(SEED)
        self.password = options['password']
        self.created = {
            'venues': 0,
            'skipped': 0,
            'customers': 0,
            'customers_skipped': 0,
            'history_bookings': 0,
            'history_orders': 0,
            'history_skipped': 0,
        }

        months = max(0, options['months'])

        with transaction.atomic():
            venues = self.seed_venues()
            self.seed_staff(venues)
            for venue in venues:
                self.seed_hours(venue)
                self.seed_spaces(venue)
                self.seed_menu(venue)
                self.seed_photos(venue)
            self.seed_reservations(venues)
            self.seed_orders(venues)
            customers = self.seed_customers(venues)
            # Last, and deliberately: the near-term seeding above skips a
            # venue that already has bookings, so filling in six months first
            # would leave today empty — the one day a demo opens on.
            self.seed_history(venues, months)

        if options['verbosity']:
            self.report(venues, customers, months)

    # --- Venues -----------------------------------------------------------

    def seed_venues(self):
        venues = []
        places = [(c, *rest) for c, *rest in CONAKRY] + [
            (c, *rest) for c, *rest in LABE
        ]

        entries = [(name, tag, Establishment.Type.RESTAURANT)
                   for name, tag in RESTAURANTS]
        entries += [(name, tag, Establishment.Type.LOUNGE)
                    for name, tag in LOUNGES]

        for index, (name, tagline, kind) in enumerate(entries):
            existing = Establishment.objects.filter(name=name).first()
            if existing is not None:
                self.created['skipped'] += 1
                venues.append(existing)
                continue

            area, lat, lon = places[index % len(places)]
            city = 'Labé' if area in {'Labé Centre', 'Daka'} else 'Conakry'
            # Jitter so venues in one area are not stacked on one pin.
            lat += self.rng.uniform(-0.012, 0.012)
            lon += self.rng.uniform(-0.012, 0.012)

            kind_label = (
                'Restaurant'
                if kind == Establishment.Type.RESTAURANT
                else 'Lounge'
            )
            venue = Establishment.objects.create(
                name=name,
                type=kind,
                city=city,
                address=f'{area}, {city}',
                latitude=Decimal(f'{lat:.6f}'),
                longitude=Decimal(f'{lon:.6f}'),
                tagline=tagline,
                description=(
                    f'{tagline}. {kind_label} à {area}, '
                    f'ouvert toute la semaine.'
                ),
                # Spread across all five, so branding is visibly per-venue.
                theme_preset=PRESETS[index % len(PRESETS)],
            )
            venues.append(venue)
            self.created['venues'] += 1

        return venues

    # --- People -----------------------------------------------------------

    def seed_staff(self, venues):
        """One owner per venue, plus a manager and a member of staff.

        Usernames are predictable on purpose — this is a demo database, and
        being able to guess the login for a venue you are looking at is the
        whole point.
        """
        for venue in venues:
            slug = (
                venue.name.lower()
                .replace(' ', '')
                .replace("'", '')
                .replace('é', 'e')
                .replace('è', 'e')
                .replace('&', '')[:14]
            )
            for role, suffix in [
                (MerchantMembership.Role.OWNER, ''),
                (MerchantMembership.Role.MANAGER, '.mgr'),
                (MerchantMembership.Role.STAFF, '.staff'),
            ]:
                username = f'{slug}{suffix}'
                user, made = User.objects.get_or_create(
                    username=username,
                    defaults={'first_name': venue.name},
                )
                if made:
                    user.set_password(self.password)
                    user.save(update_fields=['password'])
                MerchantMembership.objects.get_or_create(
                    user=user, establishment=venue, defaults={'role': role}
                )

    # --- The venue itself -------------------------------------------------

    def seed_hours(self, venue):
        if venue.hours.exists():
            return

        lounge = venue.type == Establishment.Type.LOUNGE
        for day in range(7):
            # Most places shut one day; lounges run late, kitchens do not.
            closed = day == 0 and self.rng.random() < 0.3
            if lounge:
                opens, closes = time(17, 0), time(2, 0)
            else:
                opens, closes = time(11, 30), time(23, 0)
            if day >= 4 and lounge:
                closes = time(4, 0)

            OpeningHours.objects.create(
                establishment=venue,
                day_of_week=day,
                is_closed=closed,
                opens=None if closed else opens,
                closes=None if closed else closes,
            )

    def seed_spaces(self, venue):
        if venue.spaces.exists():
            return

        lounge = venue.type == Establishment.Type.LOUNGE
        for index in range(1, self.rng.randint(4, 8)):
            Space.objects.create(
                establishment=venue,
                name=f'Table {index}',
                type=Space.Type.TABLE,
                capacity=self.rng.choice([2, 2, 4, 4, 6]),
            )
        if lounge or self.rng.random() < 0.4:
            Space.objects.create(
                establishment=venue,
                name='Salon VIP',
                type=Space.Type.VIP_ROOM,
                capacity=self.rng.choice([8, 10, 12]),
            )
        Space.objects.create(
            establishment=venue,
            name='Terrasse',
            type=Space.Type.TERRACE,
            capacity=self.rng.choice([6, 8, 10]),
        )

    def seed_menu(self, venue):
        if venue.menu_items.exists():
            return

        lounge = venue.type == Establishment.Type.LOUNGE
        picks = [
            (MenuItem.Category.FOOD, self.rng.sample(FOOD, 3 if lounge else 7)),
            (MenuItem.Category.DRINK, self.rng.sample(DRINKS, 4)),
        ]
        if lounge:
            picks.append(
                (MenuItem.Category.CHICHA_FLAVOR, self.rng.sample(CHICHA, 5))
            )

        for category, items in picks:
            for name, description, price in items:
                # Prices vary a little by venue, as they do in life.
                nudge = self.rng.choice([0.9, 1.0, 1.0, 1.1, 1.2])
                item = MenuItem.objects.create(
                    establishment=venue,
                    name=name,
                    description=description,
                    category=category,
                    price=Decimal(f'{round(price * nudge / 500) * 500}.00'),
                    # One dish in ten is sold out, so the ordering flow meets
                    # that case without anyone having to arrange it.
                    is_available=self.rng.random() > 0.1,
                )
                if self.rng.random() < 0.5:
                    item.image.save(
                        f'{name}.jpg',
                        swatch(f'{venue.name} {name}', 800, 600),
                        save=True,
                    )

    def seed_photos(self, venue):
        if venue.photos.exists():
            return

        captions = ['La salle', 'La terrasse', 'Le bar', 'Un soir de semaine']
        for caption in self.rng.sample(captions, self.rng.randint(2, 4)):
            photo = Photo(
                establishment=venue,
                uploaded_by_role=Photo.UploaderRole.MERCHANT,
                caption=caption,
            )
            photo.image.save(
                f'{caption}.jpg',
                swatch(f'{venue.name} {caption}', seed=1),
                save=False,
            )
            photo.save()

    # --- Activity ---------------------------------------------------------

    def person(self):
        return (
            f'{self.rng.choice(FIRST_NAMES)} {self.rng.choice(SURNAMES)}',
            f'+2246{self.rng.randint(10000000, 99999999)}',
        )

    def seed_today(self, venue, spaces):
        """Give this venue a day worth opening the desk on.

        The random spread elsewhere lands on today about one night in seven,
        so most venues showed "Nothing booked today" — which demonstrates the
        empty state and nothing else. One sitting already past exercises
        marking guests arrived; the two ahead are what a merchant would be
        working.

        Safe to run repeatedly: a venue that already has something today is
        left alone, so this tops a stale database up without doubling it.
        """
        today = timezone.localdate()
        if Reservation.objects.filter(
            space__establishment=venue, datetime__date=today
        ).exists():
            return

        start = timezone.localtime(timezone.now()).replace(
            minute=0, second=0, microsecond=0
        )
        for hour, status in (
            (13, Reservation.Status.CONFIRMED),
            (19, Reservation.Status.CONFIRMED),
            (21, Reservation.Status.PENDING),
        ):
            name, phone = self.person()
            Reservation.objects.create(
                space=self.rng.choice(spaces),
                customer_name=name,
                customer_phone=phone,
                datetime=start.replace(hour=hour),
                party_size=self.rng.randint(2, 5),
                status=status,
            )

    def seed_reservations(self, venues):
        now = timezone.now()

        for venue in venues:
            spaces = list(venue.spaces.all())
            if not spaces:
                continue

            # Today first, and on every run rather than only the first.
            # Seeding is idempotent by skipping venues that already have
            # bookings, which meant a database seeded last week still opened
            # on "Nothing booked today" — the one screen a demo starts from.
            self.seed_today(venue, spaces)

            if venue.spaces.filter(reservations__isnull=False).exists():
                continue

            # Past, completed bookings — these are what make reviews possible.
            for _ in range(self.rng.randint(3, 6)):
                name, phone = self.person()
                when = now - timedelta(
                    days=self.rng.randint(1, 45),
                    hours=self.rng.randint(0, 6),
                )
                booking = Reservation.objects.create(
                    space=self.rng.choice(spaces),
                    customer_name=name,
                    customer_phone=phone,
                    datetime=when,
                    party_size=self.rng.randint(1, 6),
                    status=Reservation.Status.COMPLETED,
                )
                if self.rng.random() < 0.6:
                    comment, rating = self.rng.choice(REVIEW_LINES)
                    Review.objects.create(
                        establishment=venue,
                        reservation=booking,
                        rating=rating,
                        comment=comment,
                    )

            # The days ahead, in a mix of states.
            for _ in range(self.rng.randint(2, 5)):
                name, phone = self.person()
                when = now + timedelta(
                    days=self.rng.randint(1, 6),
                    hours=self.rng.randint(1, 8),
                )
                status = self.rng.choice(
                    [
                        Reservation.Status.PENDING,
                        Reservation.Status.CONFIRMED,
                        Reservation.Status.CONFIRMED,
                        Reservation.Status.CANCELLED,
                    ]
                )
                booking = Reservation.objects.create(
                    space=self.rng.choice(spaces),
                    customer_name=name,
                    customer_phone=phone,
                    datetime=when,
                    party_size=self.rng.randint(1, 6),
                    status=status,
                )
                # Some paid up front, some paying at the venue.
                if self.rng.random() < 0.4:
                    provider = self.rng.choice(
                        [
                            Payment.Provider.ORANGE_MONEY,
                            Payment.Provider.MTN_MONEY,
                        ]
                    )
                    settled = self.rng.random() < 0.75
                    Payment.objects.create(
                        reservation=booking,
                        provider=provider,
                        amount=Decimal('50000.00'),
                        status=(
                            Payment.Status.COMPLETED
                            if settled
                            else Payment.Status.PENDING
                        ),
                        provider_reference=f'SEED-{booking.pk:08d}',
                    )

    def seed_orders(self, venues):
        """Orders, restaurants only — which is what the rule says."""
        now = timezone.now()

        for venue in venues:
            if venue.type != Establishment.Type.RESTAURANT:
                continue
            if venue.orders.exists():
                continue

            menu = list(venue.menu_items.filter(is_available=True))
            if not menu:
                continue

            # A queue with something at every stage, so the kitchen screen has
            # all of its groups filled the first time it is opened.
            plan = [
                (Order.Status.PLACED, 2),
                (Order.Status.PREPARING, 2),
                (Order.Status.READY, 1),
                (Order.Status.COMPLETED, 3),
                (Order.Status.CANCELLED, 1),
            ]

            for status, count in plan:
                for _ in range(count):
                    name, phone = self.person()
                    done = status in Order.TERMINAL_STATUSES
                    pickup = now + timedelta(
                        hours=self.rng.randint(1, 6)
                        if not done
                        else -self.rng.randint(1, 72)
                    )

                    order = Order.objects.create(
                        establishment=venue,
                        customer_name=name,
                        customer_phone=phone,
                        pickup_time=pickup,
                        status=status,
                    )
                    for item in self.rng.sample(
                        menu, min(len(menu), self.rng.randint(1, 3))
                    ):
                        OrderItem.objects.create(
                            order=order,
                            menu_item=item,
                            quantity=self.rng.randint(1, 3),
                            # Snapshotted, as the real flow does.
                            unit_price_at_order=item.price,
                        )

                    # Roughly half pay ahead. An unpaid mobile money order is
                    # deliberate: it is the one the kitchen may not start.
                    if self.rng.random() < 0.5:
                        settled = self.rng.random() < 0.7
                        Payment.objects.create(
                            order=order,
                            provider=self.rng.choice(
                                [
                                    Payment.Provider.ORANGE_MONEY,
                                    Payment.Provider.MTN_MONEY,
                                ]
                            ),
                            amount=order.total,
                            status=(
                                Payment.Status.COMPLETED
                                if settled
                                else Payment.Status.PENDING
                            ),
                            provider_reference=f'SEED-O{order.pk:07d}',
                        )

    # --- Customers --------------------------------------------------------

    def seed_customers(self, venues):
        """Signed-in customers, with a history attached to the account.

        Everything above books under a name and a phone number and no account,
        which is how most of this market will use it — but it leaves the
        customer app's signed-in half with nothing in it. Bookings, Favourites
        and Profile all read from the account, so without this they open empty
        and a demo cannot tell "nothing saved yet" from "this screen is
        broken".

        Bookings are made fresh rather than reassigned from the crowd above: a
        booking already sitting on a merchant's list belongs to whoever made
        it, and quietly moving it under an account would change what that
        merchant sees.
        """
        bookable = [v for v in venues if v.spaces.exists()]
        restaurants = [
            v
            for v in bookable
            if v.type == Establishment.Type.RESTAURANT
            and v.menu_items.filter(is_available=True).exists()
        ]
        if not bookable:
            return []

        accounts = []
        for username, first, last, phone, email in CUSTOMERS:
            user, made = User.objects.get_or_create(
                username=username,
                defaults={
                    'first_name': first,
                    'last_name': last,
                    'email': email,
                },
            )
            accounts.append((username, user))
            if not made:
                # Already seeded, or a name someone took by hand. Either way,
                # not ours to overwrite.
                self.created['customers_skipped'] += 1
                continue

            user.set_password(self.password)
            user.save(update_fields=['password'])
            CustomerProfile.objects.create(user=user, phone=phone)
            self.created['customers'] += 1

            self.seed_customer_history(user, phone, bookable, restaurants)

        return accounts

    def seed_customer_history(self, user, phone, bookable, restaurants):
        now = timezone.now()
        name = f'{user.first_name} {user.last_name}'.strip()

        # Saved venues, so Favourites opens on a list rather than on its empty
        # state. Half the value of an account is that this list is portable.
        for venue in self.rng.sample(bookable, min(len(bookable), 4)):
            Favourite.objects.get_or_create(user=user, establishment=venue)

        # One booking per state the Bookings tab groups by, so both its
        # sections and every status chip are populated for one account.
        plan = [
            (-self.rng.randint(8, 40), Reservation.Status.COMPLETED, True),
            (-self.rng.randint(2, 7), Reservation.Status.COMPLETED, False),
            (self.rng.randint(1, 3), Reservation.Status.CONFIRMED, False),
            (self.rng.randint(4, 9), Reservation.Status.PENDING, False),
            (self.rng.randint(2, 6), Reservation.Status.CANCELLED, False),
        ]

        for offset, status, reviewed in plan:
            venue = self.rng.choice(bookable)
            spaces = list(venue.spaces.all())
            when = (now + timedelta(days=offset)).replace(
                minute=0, second=0, microsecond=0
            )
            # Inside opening hours either way — a lounge at 20:00 and a
            # kitchen at 20:00 are both open.
            when = when.replace(hour=self.rng.choice([19, 20, 21]))

            booking = Reservation.objects.create(
                space=self.rng.choice(spaces),
                customer=user,
                customer_name=name,
                customer_phone=phone,
                datetime=when,
                party_size=self.rng.randint(2, 6),
                status=status,
            )

            # A confirmed booking paid ahead is what the payment card on the
            # booking detail screen is for.
            if status == Reservation.Status.CONFIRMED:
                Payment.objects.create(
                    reservation=booking,
                    provider=Payment.Provider.ORANGE_MONEY,
                    amount=Decimal('50000.00'),
                    status=Payment.Status.COMPLETED,
                    provider_reference=f'SEED-C{booking.pk:07d}',
                )

            # Reviews hang off a visit that happened, which is the rule the
            # app enforces — so only a completed one can carry one.
            if reviewed and not hasattr(booking, 'review'):
                comment, rating = self.rng.choice(REVIEW_LINES)
                Review.objects.create(
                    establishment=venue,
                    reservation=booking,
                    rating=rating,
                    comment=comment,
                )

        if not restaurants:
            return

        # Orders, restaurants only — and one still cooking, so the account has
        # something live to follow rather than only receipts.
        for status, hours in (
            (Order.Status.COMPLETED, -self.rng.randint(24, 200)),
            (Order.Status.PREPARING, self.rng.randint(1, 4)),
        ):
            venue = self.rng.choice(restaurants)
            menu = list(venue.menu_items.filter(is_available=True))
            order = Order.objects.create(
                establishment=venue,
                customer=user,
                customer_name=name,
                customer_phone=phone,
                pickup_time=now + timedelta(hours=hours),
                status=status,
            )
            for item in self.rng.sample(menu, min(len(menu), 2)):
                OrderItem.objects.create(
                    order=order,
                    menu_item=item,
                    quantity=self.rng.randint(1, 2),
                    unit_price_at_order=item.price,
                )

    # --- Six months behind us ---------------------------------------------

    def pick(self, outcomes):
        """One value from (value, weight) pairs."""
        return self.rng.choices(
            [value for value, _ in outcomes],
            weights=[weight for _, weight in outcomes],
        )[0]

    def shaped_count(self, base, popularity, day, start, span):
        """How many things happen at this venue on this day.

        Three multipliers, each answering a question a merchant would ask of
        the insights screen: which nights are busy (weekday), is this venue
        busier than that one (popularity), and are we growing (trend). The
        fractional remainder is spent as a probability rather than rounded
        away, so a venue expecting 0.4 covers on a Monday gets one about two
        Mondays in five instead of never.
        """
        trend = 0.75 + 0.45 * ((day - start).days / span)
        expected = base * popularity * WEEKDAY_WEIGHT[day.weekday()] * trend
        whole = int(expected)
        return whole + (1 if self.rng.random() < expected - whole else 0)

    def occupies(self, space_id, when, duration):
        """Every quarter-hour bucket a booking on this space would hold.

        There is no database constraint against double-booking — the rule
        lives in the availability logic the API goes through, and bulk_create
        does not go through it. Without this a seeded history would contain
        the exact clashes the product exists to prevent, and a merchant
        opening a busy Saturday would find two parties on one table.

        Both ends are snapped down to a fixed grid so that bookings made on
        arbitrary minutes — which the near-term seeding above produces — land
        in comparable buckets. Two bookings overlap exactly when their bucket
        sets intersect; snapping the *last* bucket from `start + duration - 1`
        rather than from `start` is what keeps the tail of a booking made at
        21:17 from being lost.
        """
        step = 15

        def snap(moment):
            moment = moment.replace(second=0, microsecond=0)
            return moment - timedelta(minutes=moment.minute % step)

        buckets = []
        cursor = snap(when)
        last = snap(when + timedelta(minutes=duration - 1))
        while cursor <= last:
            buckets.append((space_id, cursor))
            cursor += timedelta(minutes=step)
        return buckets

    def seed_history(self, venues, months):
        """Fill the months behind today with trading that has shape.

        Additive and idempotent on the same terms as everything else: a venue
        whose window is already full is left alone, so this tops a database up
        rather than doubling it.
        """
        if months <= 0:
            return

        today = timezone.localdate()
        # 30.4 rather than 30: six months should reach back six months, and
        # the accumulated fortnight matters at the far end of a 90-day window.
        start = today - timedelta(days=round(months * 30.4))
        span = max((today - start).days, 1)
        tz = timezone.get_current_timezone()
        duration = settings.RESERVATION_DURATION_MINUTES
        window_start = timezone.make_aware(
            datetime.combine(start, time(0, 0)), tz
        )

        planned = []
        for venue in venues:
            spaces = list(venue.spaces.all())
            if not spaces:
                continue

            existing = list(
                Reservation.objects.filter(
                    space__establishment=venue
                ).values_list('space_id', 'datetime')
            )

            # Volume in the window, not age, decides whether this venue has
            # been done. Age cannot tell the two apart: with `--months 1` the
            # whole history lands inside the 45 days the near-term seeding
            # already writes into, and an age test would either skip every
            # venue or seed them all twice.
            if (
                sum(1 for _, when in existing if when >= window_start)
                >= SEEDED_PER_MONTH * months
            ):
                self.created['history_skipped'] += 1
                continue

            grace = no_show_window(venue)
            popularity = self.rng.uniform(0.7, 1.6)
            regulars = [self.person() for _ in range(REGULARS_PER_VENUE)]
            hours = SERVICE_HOURS[venue.type == Establishment.Type.LOUNGE]
            closed = set(
                venue.hours.filter(is_closed=True).values_list(
                    'day_of_week', flat=True
                )
            )

            # Pre-load what is already booked, or the history would clash with
            # the near-term bookings written minutes ago — which occupy the
            # same weeks and were never checked against anything.
            taken = set()
            for space_id, when in existing:
                taken.update(self.occupies(space_id, when, duration))

            day = start
            while day < today:
                if day.weekday() in closed:
                    day += timedelta(days=1)
                    continue

                for _ in range(
                    self.shaped_count(
                        BASE_COVERS_PER_DAY, popularity, day, start, span
                    )
                ):
                    name, phone = (
                        self.rng.choice(regulars)
                        if self.rng.random() < REGULAR_SHARE
                        else self.person()
                    )
                    space = self.rng.choice(spaces)
                    when = timezone.make_aware(
                        datetime.combine(
                            day,
                            time(
                                self.rng.choice(hours),
                                self.rng.choice([0, 0, 30]),
                            ),
                        ),
                        tz,
                    )

                    buckets = self.occupies(space.id, when, duration)
                    if any(bucket in taken for bucket in buckets):
                        continue
                    taken.update(buckets)

                    status = self.pick(PAST_OUTCOMES)
                    booking = Reservation(
                        space=space,
                        customer_name=name,
                        customer_phone=phone,
                        datetime=when,
                        party_size=self.rng.randint(1, 6),
                        status=status,
                        # bulk_create does not call save(), so the grace
                        # period this booking was taken under has to be set
                        # here or every historical row reads as "taken before
                        # the field existed" and the no-show sweep skips it.
                        no_show_after_minutes=grace,
                        arrived_at=(
                            when + timedelta(minutes=self.rng.randint(-5, 25))
                            if status == Reservation.Status.COMPLETED
                            else None
                        ),
                    )
                    planned.append(
                        (
                            booking,
                            venue,
                            self.rng.random() < 0.38,
                            status == Reservation.Status.COMPLETED
                            and self.rng.random() < 0.22,
                        )
                    )

                day += timedelta(days=1)

        if planned:
            Reservation.objects.bulk_create(
                [booking for booking, _, _, _ in planned], batch_size=BATCH
            )
            self.created['history_bookings'] = len(planned)
            self.attach_money_and_verdicts(planned)

        # Outside the guard above: a database whose bookings are already
        # seeded may still have no kitchen history, and the two are counted
        # separately.
        self.seed_order_history(venues, months, start, span, today, tz)

    def attach_money_and_verdicts(self, planned):
        """Payments and reviews for the history just written.

        Separate pass because both hang off a reservation id, and there are
        no ids until the bookings are in.
        """
        payments, reviews = [], []
        for booking, venue, wants_payment, wants_review in planned:
            if wants_payment:
                paid = self.rng.random() < 0.82
                payment = Payment(
                    reservation=booking,
                    provider=self.rng.choice(
                        [Payment.Provider.ORANGE_MONEY, Payment.Provider.MTN_MONEY]
                    ),
                    amount=Decimal('50000.00'),
                    status=(
                        Payment.Status.COMPLETED
                        if paid
                        else Payment.Status.FAILED
                    ),
                    provider_reference=f'SEED-H{booking.pk:08d}',
                )
                payments.append(
                    (
                        payment,
                        booking.datetime
                        - timedelta(hours=self.rng.randint(1, 72)),
                    )
                )

            if wants_review:
                comment, rating = self.rng.choice(REVIEW_LINES)
                review = Review(
                    establishment=venue,
                    reservation=booking,
                    rating=rating,
                    comment=comment,
                )
                reviews.append(
                    (
                        review,
                        booking.datetime
                        + timedelta(hours=self.rng.randint(2, 60)),
                    )
                )

        self.write_backdated(Payment, payments)
        self.write_backdated(Review, reviews)

    def write_backdated(self, model, rows):
        """Write rows, then put them back where they belong in time.

        `created_at` is auto_now_add. bulk_create honours that through the
        field's pre_save, which stamps this minute onto the *instance* as well
        as the row — so setting created_at before the insert is silently
        undone, and a second pass reading it back finds only now.

        It matters beyond tidiness: the CSV export filters payments by
        created_at. Left stamped with today, six months of takings would all
        land on one day and every historical export would come back empty
        while the screens above it still looked full.
        """
        if not rows:
            return

        objects = [obj for obj, _ in rows]
        model.objects.bulk_create(objects, batch_size=BATCH)
        for obj, when in rows:
            obj.created_at = when
        model.objects.bulk_update(objects, ['created_at'], batch_size=BATCH)

    def seed_order_history(self, venues, months, start, span, today, tz):
        """The same months of kitchen work, restaurants only."""
        window_start = timezone.make_aware(
            datetime.combine(start, time(0, 0)), tz
        )
        lines = []
        written = 0

        for venue in venues:
            if venue.type != Establishment.Type.RESTAURANT:
                continue
            if (
                venue.orders.filter(pickup_time__gte=window_start).count()
                >= SEEDED_PER_MONTH * months
            ):
                continue
            menu = list(venue.menu_items.filter(is_available=True))
            if not menu:
                continue

            popularity = self.rng.uniform(0.7, 1.6)
            planned = []

            day = start
            while day < today:
                for _ in range(
                    self.shaped_count(
                        BASE_ORDERS_PER_DAY, popularity, day, start, span
                    )
                ):
                    name, phone = self.person()
                    pickup = timezone.make_aware(
                        datetime.combine(
                            day,
                            time(
                                self.rng.choice([12, 13, 13, 19, 20, 20, 21]),
                                self.rng.choice([0, 15, 30, 45]),
                            ),
                        ),
                        tz,
                    )
                    order = Order(
                        establishment=venue,
                        customer_name=name,
                        customer_phone=phone,
                        pickup_time=pickup,
                        status=self.pick(ORDER_OUTCOMES),
                    )
                    planned.append(
                        (
                            order,
                            pickup
                            - timedelta(minutes=self.rng.randint(20, 180)),
                        )
                    )
                day += timedelta(days=1)

            self.write_backdated(Order, planned)
            written += len(planned)

            for order, _ in planned:
                for item in self.rng.sample(
                    menu, min(len(menu), self.rng.randint(1, 3))
                ):
                    lines.append(
                        OrderItem(
                            order=order,
                            menu_item=item,
                            quantity=self.rng.randint(1, 3),
                            unit_price_at_order=item.price,
                        )
                    )

        OrderItem.objects.bulk_create(lines, batch_size=BATCH)
        self.created['history_orders'] = written

    # --- Report -----------------------------------------------------------

    def slug_for(self, venue):
        return (
            venue.name.lower()
            .replace(' ', '')
            .replace("'", '')
            .replace('é', 'e')
            .replace('è', 'e')
            .replace('&', '')[:14]
        )

    def report(self, venues, customers, months=0):
        out = self.stdout
        restaurants = sum(
            1 for v in venues if v.type == Establishment.Type.RESTAURANT
        )
        lounges = len(venues) - restaurants

        out.write(self.style.SUCCESS('Seeded.'))
        out.write(
            f'  venues        {len(venues)} '
            f'({restaurants} restaurants, {lounges} lounges) — '
            f'{self.created["venues"]} new, {self.created["skipped"]} already there'
        )
        out.write(f'  menu items    {MenuItem.objects.count()}')
        out.write(f'  photos        {Photo.objects.count()}')
        out.write(f'  spaces        {Space.objects.count()}')
        out.write(f'  bookings      {Reservation.objects.count()}')
        out.write(f'  orders        {Order.objects.count()}')
        out.write(f'  reviews       {Review.objects.count()}')
        out.write(f'  payments      {Payment.objects.count()}')
        out.write(
            f'  customers     {len(customers)} — '
            f'{self.created["customers"]} new, '
            f'{self.created["customers_skipped"]} already there'
        )
        if months:
            first = Reservation.objects.order_by('datetime').first()
            out.write('')
            out.write(
                f'  history       {months} months — '
                f'{self.created["history_bookings"]} bookings, '
                f'{self.created["history_orders"]} orders, '
                f'{self.created["history_skipped"]} venues already had some'
            )
            if first is not None:
                out.write(
                    f'  oldest        {timezone.localtime(first.datetime):%Y-%m-%d}'
                )
        out.write('')
        out.write(f'Password for every seeded account: {self.password}')
        out.write('')
        out.write('Merchant logins — <venue>, <venue>.mgr, <venue>.staff')
        out.write('  Restaurants (these have the kitchen queue):')
        for venue in venues:
            if venue.type == Establishment.Type.RESTAURANT:
                out.write(f'    {venue.name:24} {self.slug_for(venue)}')
        out.write('  Lounges (no orders — restaurants only, by rule):')
        for venue in venues:
            if venue.type == Establishment.Type.LOUNGE:
                out.write(f'    {venue.name:24} {self.slug_for(venue)}')
        out.write('')
        out.write('Customer logins')
        for username, user in customers:
            profile = getattr(user, 'customer_profile', None)
            contact = ', '.join(
                filter(None, [profile.phone if profile else '', user.email])
            )
            out.write(f'    {username:12} {contact or "no contact details"}')
