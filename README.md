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
- No API endpoints yet (`api/` and `payments/` are registered but empty)
- Payment/deposit fields deliberately left off Reservation until the payments
  round