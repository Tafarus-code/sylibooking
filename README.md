# Sylibooking — Backend

Django + DRF backend for the Sylibooking reservation platform (hookah lounges
and restaurants in Guinea). See `CLAUDE.md` for the product brief and MVP scope.

## Quick start (SQLite — zero setup)

The default environment is `local`, which uses SQLite at `backend/db.sqlite3`.
No PostgreSQL, no Docker, nothing to install beyond the requirements.

```bash
python -m venv .venv
.venv\Scripts\activate         # Windows;  source .venv/bin/activate on macOS/Linux
pip install -r requirements.txt

cp .env.example .env           # then set SECRET_KEY (see below)

python backend/manage.py migrate
python backend/manage.py createsuperuser
python backend/manage.py runserver
```

Admin panel: http://127.0.0.1:8000/admin/ — create establishments, spaces and
reservations by hand there. That is the intended way to seed test data at this
stage; there is no API yet.

Generate a secret key with:

```bash
python -c "from django.core.management.utils import get_random_secret_key as k; print(k())"
```

## Environment variables

`.env` lives at the repo root (or in `backend/` — settings searches from
`backend/` upward). `.env.example` lists everything; `.env` itself is gitignored.

| Variable | Default | Notes |
| --- | --- | --- |
| `DJANGO_ENV` | `local` | `local` → SQLite, `production` → PostgreSQL |
| `SECRET_KEY` | — | Required in both environments |
| `DEBUG` | `False` | Set `True` locally |
| `ALLOWED_HOSTS` | `localhost,127.0.0.1` | Comma-separated |
| `CORS_ALLOWED_ORIGINS` | empty | Production only, comma-separated. See below |

### CORS (browser builds only)

Running either app in Chrome makes every API call cross-origin, and the browser
blocks it unless Django says otherwise:

```
Access to fetch at 'http://127.0.0.1:8000/api/auth/login/' from origin
'http://localhost:58966' has been blocked by CORS policy
```

Locally this is handled for you — `DJANGO_ENV=local` allows any origin, because
`flutter run -d chrome` serves from a new random port on every run. Android and
iOS are not affected at all.

In production the allowlist is explicit and fails closed: set
`CORS_ALLOWED_ORIGINS=https://app.sylibooking.com` (comma-separated for several).
Leaving it unset means no browser origin is permitted, which is the right
default for an API serving only mobile builds.

## Switching to PostgreSQL

Set `DJANGO_ENV=production` and add the `DB_*` variables:

```
DJANGO_ENV=production
SECRET_KEY=a-different-generated-key
DEBUG=False
ALLOWED_HOSTS=your.domain

DB_NAME=sylibooking
DB_USER=sylibooking
DB_PASSWORD=...
DB_HOST=localhost     # optional, defaults to localhost
DB_PORT=5432          # optional, defaults to 5432
```

`DB_NAME`, `DB_USER` and `DB_PASSWORD` are required when `DJANGO_ENV=production`
— startup fails loudly if any is missing. Then create the database and run
`python backend/manage.py migrate` again against it. The same migrations apply
to both backends; nothing in the models is SQLite-specific.

## API

Browsable at http://127.0.0.1:8000/api/ once the server is running. Log in for
the merchant-only endpoints at `/api-auth/login/` or `/admin/`.

| Method | Endpoint | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/api/auth/login/` | public | Username + password → token |
| `POST` | `/api/auth/logout/` | merchant | Invalidate the caller's token |
| `GET` | `/api/auth/me/` | merchant | Who am I, and which venues do I staff |
| `GET` | `/api/establishments/` | public | Browse; filters: `city`, `type`, `search` |
| `GET` | `/api/establishments/{id}/` | public | Detail with its spaces |
| `GET` | `/api/establishments/{id}/availability/` | public | Slot grid; params: `date` (required), `party_size` |
| `POST` | `/api/reservations/` | public | Book a slot — always created `pending` |
| `GET` | `/api/reservations/ref/{reference}/` | reference | The customer's own booking |
| `GET` | `/api/reservations/ref/{reference}/payment/` | reference | Poll the provider; confirms the booking when paid |
| `POST` | `/api/reservations/ref/{reference}/cancel/` | reference | Customer cancels, freeing the slot |
| `GET` | `/api/reservations/{id}/` | merchant | Scoped to the caller's venues |
| `GET` | `/api/reservations/` | merchant | Filters: `establishment`, `status`, `date`, `date_from`, `date_to` |
| `POST` | `/api/reservations/{id}/confirm/` | merchant | Accept a booking |
| `POST` | `/api/reservations/{id}/cancel/` | merchant | Turn it down, freeing the slot |

Booking a slot:

```bash
curl -X POST http://127.0.0.1:8000/api/reservations/ \
  -H 'Content-Type: application/json' \
  -d '{"space": 1, "customer_name": "Mariama Diallo",
       "customer_phone": "+224 620 00 00 00",
       "datetime": "2026-08-01T19:00:00Z", "party_size": 2}'
```

### Opening hours and menu

`OpeningHours` holds one row per weekday per establishment. **A closing time
earlier than the opening time means the venue runs past midnight** — 18:00 to
02:00 is the ordinary case for a lounge in Conakry, not an edge case. That
interval belongs to the day it *starts* on, so Monday 18:00–02:00 covers Tuesday
01:00, and answering "is it open at 1am?" has to consult *yesterday's* row.

That arithmetic lives in `establishments/hours.py` and is computed server-side,
so both apps agree and it exists once rather than once per client. The API sends
`is_open_now` and `closes_at` on both the list and detail endpoints, plus
`today` and all seven days on detail.

Three rules worth knowing:

- **A day with no row is closed**, and an establishment with no hours at all
  reports `today: null` — the apps show "Hours not listed" rather than guessing
  "Closed". Silence is not the same as shut.
- **`today` is only ever the current day.** Never a fallback to a neighbouring
  day or a default, which would tell a customer a shut venue is open.
- **`week_schedule` always returns seven rows**, filling unset days with a
  closed placeholder, so a venue that listed five days still renders a full week.

`MenuItem` carries a category (`food`, `drink`, `chicha_flavor`), a price in GNF
and `is_available`. The detail endpoint groups available items by category and
**omits any category with nothing available** — otherwise the app renders a
heading with nothing under it. An establishment with no menu returns `[]` and the
app shows no menu section at all, which is the common case for pilot merchants.

`Establishment.opening_hours` survives as a free-text note shown beneath the
structured hours. Nothing computes from it.

### Reviews and photos

A `Review` hangs off a **reservation**, not off a customer — one review per
booking. Since customers have no accounts, the **reservation reference is the
credential**: posting a review means sending the reference issued at booking.
The rules the server enforces:

- The booking must be **`completed`**. Confirmed is not the same as been there.
- The booking must belong to **this** establishment.
- One review per booking, so a regular reviews each visit separately.

A wrong-venue reference and a made-up one return the *same* message, so the
error cannot be used to probe for valid references. Reviews publish the
customer's **first name only** — the booking holds a full name and a phone
number, and a public review needs neither.

Photos accept either credential: a customer sends a reservation reference (any
status — someone turned away still has something to show), a merchant sends
their token and must staff the establishment. Uploads are size- and
extension-checked, and the original filename is discarded, since it can carry a
customer's name and two people's `IMG_0001.jpg` must not collide.

`is_hidden` on both models is moderation-only and **never appears in any
customer-facing response**. Hidden reviews are excluded from the list *and* from
`average_rating`, which is computed on read rather than stored — a stored
average would drift the moment something was hidden.

| Endpoint | Auth |
| --- | --- |
| `GET /api/establishments/{id}/reviews/` | public, paginated, newest first |
| `POST /api/establishments/{id}/reviews/` | reservation reference |
| `GET /api/establishments/{id}/photos/` | public, paginated |
| `POST /api/establishments/{id}/photos/` | reservation reference, or merchant token |

Both apps can upload. The customer sends a photo from any of their bookings in
**My bookings**; the merchant adds venue photos and menu-item pictures from
**Manage**. Picking an image goes through an `ImageSource` interface rather than
calling `image_picker` directly, so the upload paths are exercised in widget
tests — a platform channel cannot run in one.

**A venue photo is profile work: owner and manager only.** The endpoint used to
accept any member, which meant the server said yes to something the app never
offered a staff user. Menu-item pictures follow the same rule, and are attached
with a multipart `PATCH` separate from the JSON item update — otherwise every
text edit would become an upload.

Uploads land in `MEDIA_ROOT` (`backend/media/`, gitignored) and Django serves
them **only when `DEBUG` is on**. In production a web server or object store
must serve `MEDIA_URL`; `MAX_PHOTO_UPLOAD_BYTES` (5 MB) and
`ALLOWED_PHOTO_EXTENSIONS` are settings.

### How availability works

`Reservation` stores only a start time, so every booking is treated as running
for `RESERVATION_DURATION_MINUTES` (default 120). Two bookings on one space
clash when those windows overlap, which is what blocks double-booking. Slots are
offered on an `AVAILABILITY_SLOT_MINUTES` grid (default 30) between
`AVAILABILITY_WINDOW_START` and `AVAILABILITY_WINDOW_END` — all in
`config/settings.py`.

Those three are global because `Establishment.opening_hours` is still free text
and cannot be parsed. They become per-establishment once it is structured.

A cancelled reservation frees its slot; pending, confirmed and completed all
hold it.

## Customer app (Flutter)

`apps/customer_app` — browse lounges and restaurants, pick a day, party size and
time, and reserve. Pay-on-arrival only; nothing is charged.

```bash
cd backend && python manage.py runserver
cd apps/customer_app && flutter run
```

**A customer account is optional, and nothing in the booking flow requires
one.** A booking is a name and a phone number. Every reservation gets a
**reference** (a UUID) at creation, and holding it is what proves the booking is
yours — it is how **My bookings** reads the live status and how a customer
cancels. The app stores references on the device; clearing app data loses that
list, but the booking still stands at the venue, and staff can find it by
reference in `/admin/`.

An account buys exactly two things: the list survives a lost phone, and
favourites become portable. Signing in *claims* whatever references are on the
device into the account, so nothing made while signed out is stranded. Register,
sign in, profile editing, password reset by SMS or email, and account closure
all exist — see `api/customer_accounts.py`.

Reservations are *not* reachable by their sequential id without merchant
credentials. They were once, which meant counting `1, 2, 3…` returned other
people's names and phone numbers.

At the booking step the customer picks pay-on-arrival (the default) or a mobile
money provider. Paying confirms the table immediately; the confirmation screen
polls until the payment settles and says plainly when nothing was charged. See
[Payments](#payments) for what the server does with that choice.

Customers can cancel a booking that has not started yet; the slot goes straight
back on sale. Once it has started — or the visit is marked completed — the
server refuses and the app says to call the venue instead, rather than letting
someone rewrite what happened. Cancelling twice is a no-op, not an error, since
a customer on a flaky connection will tap twice.

Customers pick a *time*, not a table. `bookableTimes()` in `shared_client`
collapses the per-space availability grid into the times that are free, choosing
the smallest space that seats the party so a couple does not take the VIP room.

## Establishment branding

Five curated presets — Ember (default), Palm Night, Harmattan, Bissap, Indigo
Soir — each pairing a display font, a body font, an accent, and a text colour
pre-verified against that accent for WCAG AA. **No colour picker and no font
picker:** a merchant chooses a key, and `theme_preset` is the only thing stored.
That is what lets every venue stay legible.

`design/theme_presets.json` is the single source of truth. The backend reads it
at import; `shared_client` mirrors it in Dart, and a test compares the two so
they cannot drift. Contrast is **recomputed from the hex values** by tests on
both sides, so "pre-verified" is checked rather than asserted.

Theming is **scoped, never global**. `EstablishmentThemeScope` wraps only the
customer's establishment detail screen and the merchant's branding preview.
Bottom navigation, browse, settings and the venue switcher keep the app's own
theme, so moving between venues never makes the app itself look like it changed.
An unknown preset key falls back to the default rather than failing — a newer
server may know presets an older build does not.

Fonts come from `google_fonts` at runtime rather than being bundled per app.

## Distance and directions

No map SDK. Distance is computed client-side with the haversine formula in
`shared_client/lib/src/geo.dart`, and "Get directions" hands off to a `geo:`
URI — whatever maps app the customer already has and trusts, with an
`https://google.com/maps` fallback for devices with no `geo:` handler.

The whole feature is optional, and the app is built so that nothing depends on
it:

- **Browsing never opens with a permission prompt.** A fix is only requested on
  launch if permission was already granted. Otherwise a "Show distances" chip
  explains *why* before prompting, so a refusal is an informed one.
- **Denied, GPS off, and no-fix are told apart** and get different wording. None
  of them is an error state; the list renders exactly as before, minus distance.
- **Sort-by-distance only exists once there is a position to sort by.**
- **A venue with no coordinates has no distance** and sorts to the bottom rather
  than behaving as if it were at the origin. Most venues start this way, since
  `latitude`/`longitude` are optional.

Directions need only the *venue's* coordinates, so that button works with no
location permission at all.

`latitude`/`longitude` arrive as **strings** — DRF serialises `DecimalField`
that way — so the client parses either a string or a number.

## Merchant roles and venues

`MerchantMembership` is the through model for `Establishment.staff`: access and
authority are the same relationship, so one row carries both who may work here
and how far that goes.

| | Owner | Manager | Staff |
| --- | :-: | :-: | :-: |
| Reservations, confirm/cancel, payment status | ✓ | ✓ | ✓ |
| Toggle menu availability (sold out) | ✓ | ✓ | ✓ |
| Edit profile: hours, menu, photos, description | ✓ | ✓ | — |
| Add/remove members, change roles | ✓ | — | — |

**Staff toggling availability is deliberate**, and the one exception to profile
editing. Marking a dish sold out is a floor decision taken mid-service; routing
it through a manager would mean customers ordering things the kitchen has run
out of. The toggle endpoint accepts nothing but `is_available`, so it cannot be
used as a back door into pricing.

Three rules worth knowing:

- **A non-member gets 404, a member with too low a role gets 403.** Confirming
  that a venue exists and that you merely lack rights tells an outsider more
  than they need; a member is entitled to know why.
- **Role changes take effect on the caller's very next request.** Permissions
  are read from the database per request and never cached on the token, so no
  re-login is needed — and revoking access is immediate.
- **The last owner cannot be demoted or removed.** A venue nobody can
  administer is not a state worth allowing.

Listings are **no longer merged across venues**. `GET /api/reservations/` and
the payments dashboard both require `?establishment=<id>` and refuse a venue the
caller has no membership in. Merchants with one venue never see a switcher; the
app only offers one to accounts that have somewhere to switch to.

## Merchant payments dashboard

`GET /api/dashboard/payments/?date_from=&date_to=` — scoped to the caller's own
venues, defaulting to the last 30 days. It answers the three questions a venue
owner actually asks at the end of a shift: what did I take, what is still owed,
and who do I chase.

Two details worth knowing:

- **Cash is counted but carries no figure.** Cash bookings write no `Payment`
  row, so their count comes from reservations with no payment attached —
  otherwise the busiest column on the dashboard would simply be missing. The
  money column reads "at the till", because it never passes through us.
- **"Needs chasing" ignores the reporting window.** A booking next month whose
  payment failed is the one worth acting on today, so it appears regardless of
  the dates selected. It lists only *upcoming*, still-pending bookings — chasing
  money for a night that already passed is pointless.

## Merchant app (Flutter)

Three tabs: **Reservations**, **Payments**, **Manage**. Manage is the way into
the venue itself — menu, opening hours, venue details, and who has access.

**Entries a role cannot use are absent, not disabled.** A manager sees no "Who
has access"; staff see only the menu, with a line saying who to ask. The server
refuses either way — the UI simply does not offer a button that would always
fail. The menu is the deliberate exception: staff belong there, because marking
a dish sold out is theirs to do.

`apps/merchant_app` — sign in, see today's or the next seven days' bookings,
confirm or cancel. `apps/shared_client` holds the API models and HTTP client
that both apps will share.

```bash
cd backend && python manage.py runserver     # the app needs the API running
cd apps/merchant_app && flutter run
```

The app defaults to `http://10.0.2.2:8000/api` on Android (the emulator's route
to the host) and `http://127.0.0.1:8000/api` elsewhere. Point it somewhere else
at build time:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
```

### Giving an account access to a venue

The app shows only the reservations of establishments the signed-in user staffs.
A brand new user sees an empty list until assigned:

1. `python backend/manage.py createsuperuser` (or add a normal user in `/admin/`)
2. In `/admin/` → Establishments → pick one → add the user under **Staff**

Superusers see every establishment's bookings.

## Payments

`POST /api/reservations/` takes an optional `payment_provider`:

| Value | What happens |
| --- | --- |
| `cash_on_arrival` (default) | Exactly as before — no Payment row, booking stays `pending` for the merchant to confirm by hand |
| `orange_money` / `mtn_money` | A Payment is opened and the provider called; the booking becomes `confirmed` **only** once that payment completes |

Nothing talks to a real provider yet. Every provider resolves to
`MockPaymentProvider`, which always succeeds immediately:

```python
PAYMENT_PROVIDERS = {
    'orange_money': 'payments.providers.MockPaymentProvider',
    'mtn_money': 'payments.providers.MockPaymentProvider',
}
```

Real Orange Money / MTN adapters implement the same two-method
`PaymentProvider` interface — `initiate_payment` and `check_status` — so
switching one on is a change to that setting, not to the reservation flow.

The amount is `RESERVATION_DEPOSIT_AMOUNT` (default 50 000 GNF, overridable via
`.env`). It is read server-side: a client sending `amount` in the request body
is ignored, since nothing may choose what it owes. One global figure for now —
per-establishment pricing belongs on `Establishment` later.

### Confirming, and who may confirm what

One rule, enforced server-side rather than by hiding a button:

- **Cash on arrival can be confirmed before any money changes hands.** That is
  what cash on arrival means — the merchant is holding a table on trust.
- **A mobile money booking cannot be confirmed while its payment is pending or
  failed.** Holding a table against money that never arrived is the no-show the
  deposit exists to prevent. `POST .../confirm/` returns `409` with the provider
  and payment status; the merchant can still cancel it.

The reservation payload carries `can_confirm` so the app can disable the button,
but the check runs in the view regardless — the API is reachable directly.

Merchant-facing reservation payloads also carry `payment_provider`,
`payment_provider_display`, `payment_status` and `is_paid` as flat fields, so a
day's list can render a badge per row without unpacking the nested payment.
`payment_status` is null when there is nothing to settle, which is how "cash on
arrival" is told apart from "mobile money, unpaid".

A payment that fails, or a provider that cannot be reached, leaves the booking
`pending` rather than losing it. `GET .../payment/` polls the provider and
applies the result, which is how the app learns a payment settled after the
customer approved it on their handset. A completed payment never reinstates a
booking that was cancelled in the meantime.

## Demo data and test logins

```bash
cd backend
python manage.py seed_demo              # 22 venues across Conakry and Labé
python manage.py backfill_image_copies  # only needed for data seeded before
                                        # image derivatives existed
```

Additive and idempotent — running it twice changes nothing, and it never
touches rows you created by hand. It tops up today's bookings on every run, so
a database seeded last week still opens on a day with something in it.

**Every seeded account uses the password `sylibooking`.**

| Who | Username |
|---|---|
| Restaurant owner (has a kitchen queue) | `chezmariama`, `ledamier`, `lapaillote`, `lewharf`, … |
| Lounge owner (no orders — restaurants only, by rule) | `lepetitbaobab`, `kaloumnights`, `lenimba`, … |
| Manager / staff at any venue | `<venue>.mgr`, `<venue>.staff` |
| Customer | `mariama`, `sekou`, `kadiatou`, `binta` |

The venue slug is its name lowercased with spaces and accents removed, cut to
14 characters — `seed_demo` prints the full list when it finishes.

To exercise the **kitchen queue, log in as a restaurant**: a lounge has no
orders, and that is the rule working rather than a bug. The four customers
differ only in contact details — phone and email, phone only, email only, and
neither — because that is what the profile screen and password reset behave
differently about. `binta` is the account the app warns would be lost with the
phone.

## Tests and linting

```bash
pip install -r requirements-dev.txt

cd backend && python manage.py test    # must be run from backend/
ruff check .                           # from the repo root
```

Test discovery starts at the working directory, so `manage.py test` finds
nothing if you run it from the repo root — `cd backend` first.

## CI

`.github/workflows/ci.yml` runs on every push to `main`, `dev` and any
`feat/**`, `fix/**` or `chore/**` branch, and on pull requests into `main` or
`dev` — so a branch is green before it is merged, not after:

| Job | What it guards |
| --- | --- |
| `lint` | `ruff check` — style, unused imports, import order, Django-specific rules |
| `test-sqlite` | Django checks, missing-migration detection, full test suite on SQLite |
| `test-postgres` | Same suite against PostgreSQL 16 with `DJANGO_ENV=production` |
| `flutter` | `flutter analyze --fatal-infos` and `flutter test` for each Dart package |

Running the suite on both backends means the environment split in `settings.py`
is exercised, not just assumed, and `makemigrations --check --dry-run` fails the
build if a model changes without a matching migration.

The Flutter jobs run in `TZ=Pacific/Kiritimati`, fourteen hours from the
runner's UTC. That is deliberate: a test that quietly depends on the hour used
to pass on a developer's evening machine and fail every CI run before 19:00
UTC, and an unlikely zone makes that class of bug fail on the first run instead
of by time of day. Note the Dart VM on Windows ignores `TZ` and reads the OS
zone, so this is enforced in CI rather than reproducible locally.

There is still no deploy workflow. The container images and
[`deploy/render.yaml`](deploy/README.md) exist, but promotion is a deliberate
act — see [`RELEASE.md`](RELEASE.md).

## Branching

```
feat/… fix/… chore/…   →   dev   →   main
```

New work goes on a feature branch off `dev`, then merges into `dev`. `main` only
receives work promoted from `dev`, so it stays releasable. CI runs on pushes to
`main`, `dev` and any `feat/**`, `fix/**` or `chore/**` branch, plus on pull
requests targeting `main` or `dev` — so a branch is green before it merges.

## Project layout

```
backend/
  config/           Django settings, urls, wsgi/asgi
  establishments/   Establishment + Space models
  reservations/     Reservation model + availability logic
  payments/         empty for now — Payment model comes later
  api/              DRF serializers, viewsets, token auth
apps/
  shared_client/    Dart API client + models, shared by both apps
  merchant_app/     Flutter — sign in, see bookings, confirm/cancel
  customer_app/     Flutter — browse, pick a slot, reserve
```

## Current state

**Read [`PLATFORM_ASSESSMENT.md`](PLATFORM_ASSESSMENT.md) for the current
picture**, and [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) for what is
being built next. In short, as of 12 August 2026:

- 16 models, 61 API routes, both Flutter apps, English and French throughout.
- Token auth with per-venue membership and roles (owner / manager / staff).
  Every merchant route checks membership against the venue in its URL.
- Payments work end to end **against a mock provider**. Orange Money and MTN
  are the one substantial gap, and they are blocked on sandbox credentials
  rather than on code — the adapter interface is already in place.
- Celery and beat run reminders, no-show sweeps and payment polling.
- Containers, `deploy/render.yaml`, media on Cloudflare R2, and a signed
  release process.

The section this replaces described a state from before merchant auth,
payments and both apps existed. It is kept in the history rather than
corrected in place: see `git show 170a0a0:README.md`.
  Reservation until then