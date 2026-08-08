# The backend, packaged so it runs somewhere other than a laptop.
#
# One image serves all three roles — web, Celery worker, Celery beat — because
# they are the same code and differ only in the command they are given. Three
# images built from one source tree is three chances for them to drift apart
# by a deploy.

# --- build -----------------------------------------------------------------
#
# Wheels are built here and only the results are copied forward, so the
# runtime image carries no compiler. psycopg2 and Pillow are the reason: both
# need a toolchain to install and neither needs one to run.
FROM python:3.12-slim AS build

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install --no-install-recommends -y \
        build-essential \
        libpq-dev \
        libjpeg-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /wheels
COPY requirements.txt .
RUN pip wheel --wheel-dir /wheels -r requirements.txt


# --- runtime ---------------------------------------------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    # Unbuffered, or the JSON log lines from Slice 20 sit in a pipe buffer
    # and arrive minutes after the thing they describe.
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DJANGO_ENV=production

# libpq and libjpeg only — the runtime halves of what the build stage needed.
RUN apt-get update && apt-get install --no-install-recommends -y \
        libpq5 \
        libjpeg62-turbo \
    && rm -rf /var/lib/apt/lists/*

# Not root. A container that is compromised should not also be privileged.
RUN useradd --create-home --uid 10001 sylibooking

COPY --from=build /wheels /wheels
COPY requirements.txt .
RUN pip install --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels requirements.txt

WORKDIR /app
COPY --chown=sylibooking:sylibooking backend/ /app/
COPY --chown=sylibooking:sylibooking deploy/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

USER sylibooking

# Static files are baked in rather than collected at boot: every replica would
# otherwise do the same work at the same moment, and a container that cannot
# start because collectstatic failed is a deploy that fails late instead of at
# build time. A throwaway key because collectstatic reads settings and settings
# insist on one; nothing signed here ever leaves the build.
RUN SECRET_KEY=build-only-not-a-secret \
    DJANGO_ENV=local \
    python manage.py collectstatic --noinput

EXPOSE 8000
ENTRYPOINT ["/app/entrypoint.sh"]

# Overridden for the worker and beat. Gunicorn's default worker is right here:
# every view is ordinary blocking Django, and async workers would buy nothing
# but a new class of bug.
CMD ["gunicorn", "config.wsgi:application", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "3", \
     "--timeout", "60", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
