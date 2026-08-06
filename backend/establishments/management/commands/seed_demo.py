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
from datetime import time, timedelta
from decimal import Decimal
from io import BytesIO

from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone
from orders.models import Order, OrderItem
from PIL import Image, ImageDraw

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

    def handle(self, *args, **options):
        self.rng = random.Random(SEED)
        self.password = options['password']
        self.created = {'venues': 0, 'skipped': 0}

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

        self.report(venues)

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

    # --- Report -----------------------------------------------------------

    def report(self, venues):
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
        out.write('')
        out.write('Merchant logins — <venue>, <venue>.mgr, <venue>.staff')
        out.write(f'Password for all of them: {self.password}')
        out.write('')
        for venue in venues[:6]:
            slug = (
                venue.name.lower()
                .replace(' ', '')
                .replace("'", '')
                .replace('é', 'e')
                .replace('è', 'e')
                .replace('&', '')[:14]
            )
            out.write(f'  {venue.name:24} {slug}')
        if len(venues) > 6:
            out.write(f'  … and {len(venues) - 6} more')
