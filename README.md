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

There are no customer accounts: a booking is a name and a phone number. Every
reservation gets a **reference** (a UUID) at creation, and holding it is what
proves the booking is yours — it is how **My bookings** reads the live status
and how a customer cancels. The app stores references on the device; clearing
app data loses that list, but the booking still stands at the venue, and staff
can find it by reference in `/admin/`.

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

## Merchant app (Flutter)

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

A payment that fails, or a provider that cannot be reached, leaves the booking
`pending` rather than losing it. `GET .../payment/` polls the provider and
applies the result, which is how the app learns a payment settled after the
customer approved it on their handset. A completed payment never reinstates a
booking that was cancelled in the meantime.

## Tests and linting

```bash
pip install -r requirements-dev.txt

cd backend && python manage.py test    # must be run from backend/
ruff check .                           # from the repo root
```

Test discovery starts at the working directory, so `manage.py test` finds
nothing if you run it from the repo root — `cd backend` first.

## CI

`.github/workflows/ci.yml` runs on every push and pull request against `main`:

| Job | What it guards |
| --- | --- |
| `lint` | `ruff check` — style, unused imports, import order, Django-specific rules |
| `test-sqlite` | Django checks, missing-migration detection, full test suite on SQLite |
| `test-postgres` | Same suite against PostgreSQL 16 with `DJANGO_ENV=production` |
| `flutter` | `flutter analyze --fatal-infos` and `flutter test` for each Dart package |

Running the suite on both backends means the environment split in `settings.py`
is exercised, not just assumed, and `makemigrations --check --dry-run` fails the
build if a model changes without a matching migration.

No deploy workflow yet — there is no API surface to deploy, so CD gets added
once endpoints exist and a host is chosen.

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

- Models + admin for Establishment, Space, Reservation
- Read API for establishments, availability for a date, and reservation
  create/confirm/cancel
- **No real auth yet.** "Merchant" endpoints require any authenticated Django
  user, which today means a superuser. There is no customer/merchant user model
  and no per-establishment scoping, so any logged-in user can see and act on
  every establishment's reservations. That lands with the merchant app.
- `payments/` is still an empty app; payment/deposit fields are deliberately off
  Reservation until then