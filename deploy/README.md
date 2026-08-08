# Deploying Sylibooking

Everything here runs the backend somewhere other than a laptop. What is
**not** here is the choice of host — see [Still to decide](#still-to-decide).

## What exists

| Piece | Where | Notes |
|---|---|---|
| Image | `Dockerfile` | One image, three roles (web, worker, beat) |
| Boot steps | `deploy/entrypoint.sh` | Migrations, then the given command |
| Local rehearsal | `docker-compose.yml` | Postgres + Redis + all three roles |
| Settings | `.env.example` | Every variable, with defaults that work locally |
| Checks | CI job `deploy-checks` | Builds the image and boots it on every push |

## Rehearsing locally

```
cp .env.example .env        # SECRET_KEY is the only one with no default
docker compose up --build
```

That runs the production engine — Postgres, not SQLite — with the production
settings module, minus TLS. `http://localhost:8000/api/health/ready/` names
each part and says which is down.

## The two things that will bite

**Media must not live on the container's disk.** `backend/media/` is inside
the image. A redeploy replaces the container and takes every photo a merchant
uploaded with it — that is data loss on an ordinary Tuesday, and the people
who lose it are venues who spent an evening photographing their room. Set
`USE_S3_MEDIA=True` and the bucket variables before the first real upload,
not after. Any S3-compatible bucket works; the endpoint is a setting
precisely so a regional provider can be used.

**Migrations run on the web role only.** `RUN_MIGRATIONS=no` on the worker
and beat, which compose already sets. Three replicas racing one migration is
how a half-applied schema happens.

## Decided

**Host: Render** (`deploy/render.yaml`). A managed platform that builds the
Dockerfile, runs the three roles, and provides Postgres and Redis — chosen
over a bare VPS because nobody here wants to be the one patching a database
server, and over a hyperscaler because the setup cost is not repaid at this
size. Railway and Fly want the same four facts in their own format — one
image, three commands, a Postgres URL, a Redis URL — so switching is a
translation rather than a rewrite.

Pick a **European region**: it is the closest good option to Conakry, and a
US region adds a few hundred milliseconds to every request on connections
that already have little to spare.

**Media: Cloudflare R2.** S3-compatible, and no egress charge — which is the
whole argument when the heaviest thing this app serves is a venue's
photographs, over connections paid for by the megabyte.

Two R2 details that are easy to get wrong and fail confusingly:

- **No ACLs.** R2 rejects the header, so `default_acl='public-read'` fails
  every upload rather than making anything public. The setting is `None`; a
  bucket is made public by attaching a domain to it.
- **The API endpoint is not publicly readable.** Set `MEDIA_CUSTOM_DOMAIN`
  to the r2.dev subdomain or a custom domain, or every photo 401s while the
  configuration looks perfect.

## Still to do

Deployment itself, which is Slice 22 — the account, the blueprint applied,
DNS and TLS, the secrets filled in, and the first merge to `main`, which has
been deliberately untouched since the project started.

The variables marked `sync: false` in the blueprint are the ones that must be
filled in by hand: they are credentials and hostnames, and a blueprint that
carried them would be a blueprint nobody could commit.
