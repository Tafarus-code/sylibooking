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
| `GET` | `/api/reservations/{id}/` | public | Check one booking by id |
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
  reservations/     Reservation model
  payments/         empty for now — Payment model comes later
  api/              empty for now — DRF serializers/viewsets come next
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