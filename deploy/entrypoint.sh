#!/bin/sh
# What has to be true before the process starts serving.
#
# `set -e` matters more than usual here: a container that carries on after a
# failed migration serves requests against a schema it does not match, which
# looks like data corruption rather than a failed deploy.
set -e

# Migrations run on the web role only. Three replicas racing the same
# migration is how a half-applied schema happens; the worker and beat are
# given a different command and skip this.
if [ "${RUN_MIGRATIONS:-yes}" = "yes" ]; then
  echo "Applying migrations..."
  python manage.py migrate --noinput
fi

# The compiled French catalogue is committed, but a .po edited without
# recompiling is the silent failure the language tests were written to catch.
# Cheap enough to redo at boot, and it fails loudly here rather than serving
# English to a French app.
python manage.py compile_po >/dev/null 2>&1 || \
  echo "compile_po skipped (no catalogue to compile)"

exec "$@"
