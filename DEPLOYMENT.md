# Going live — what you do, and in what order

Every integration in Phase 8 is **built and tested**. None of it is switched
on, because switching one on means putting a credential into an environment
variable and nothing else. This is the list of credentials, where each comes
from, and what to paste it into.

**Nothing here changes code.** If you find yourself editing a Python file to
make a provider work, something has gone wrong — every URL, key and field name
below is a setting, deliberately, because contracts differ by country and by
merchant agreement.

---

## The order to do this in

You do not need all of it at once, and doing it all at once is how a first
deploy fails for five reasons simultaneously.

| # | Step | Blocks | Do it when |
|---|---|---|---|
| 1 | [Railway + Postgres](#1-railway-and-postgres) | everything | first |
| 1b | [The apps as web services](#1b-the-two-apps-as-web-services) | browser access to either app | after the API answers |
| 2 | [Cloudflare R2](#2-cloudflare-r2-for-images) | photo uploads | before any real merchant uploads a photo |
| 3 | [Redis + worker + beat](#3-redis-the-worker-and-beat) | reminders, no-show sweeps, payment polling | with step 1 |
| 4 | [SMS gateway](#4-sms) | reminders and password resets actually arriving | before a pilot |
| 5 | [Orange Money](#5-orange-money) | taking money | when Orange issues sandbox keys |
| 6 | [MTN MoMo](#6-mtn-mobile-money) | taking money | after Orange works |
| 7 | [Firebase](#7-firebase-push) | merchant alerts without pulling to refresh | any time |
| 8 | [WhatsApp](#8-whatsapp-optional) | a channel some venues prefer | last, optional |

A useful checkpoint: after steps 1–3 the whole product works in production
against the **mock** payment provider. That is a real, usable pilot for a
venue taking cash on arrival — which is most of them, most of the time.

---

## 1. Railway and Postgres

### Create the services

1. New project on Railway, then **Deploy from GitHub repo** → your
   `sylibooking` repo, branch **`main`**. `main` means what is deployed; see
   [`RELEASE.md`](RELEASE.md).
2. Add a **PostgreSQL** database to the project. Railway sets `DATABASE_URL`
   automatically and the app reads it.
3. Railway reads [`railway.json`](railway.json): build from the `Dockerfile`,
   health check `/api/health/`, restart on failure up to three times. The
   image collects static files at build time; `deploy/entrypoint.sh` runs
   migrations on boot and then starts gunicorn.

Three things are already handled so you do not have to find them the hard
way:

* **The port.** Gunicorn binds `$PORT`, which Railway injects. A container
  that hardcodes 8000 deploys green and 502s every request.
* **The health check host.** Railway sends it with
  `Host: healthcheck.railway.app`, which Django would answer with a 400 —
  a healthy service failing its check and being restarted forever. That
  host, and Railway's public and private domains, are added to
  `ALLOWED_HOSTS` automatically.
* **Workers.** `WEB_CONCURRENCY` sets the gunicorn worker count; the default
  of 3 is too many for a 512MB container. Set it to 2 there.

### Variables

Set these on the **web** service. Anything not listed has a working default.

```
DJANGO_ENV=production
SECRET_KEY=<generate one, see below>
DEBUG=False
```

`ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` only need setting once you put a
custom domain in front — Railway's own domain is added for you. With one:

```
ALLOWED_HOSTS=api.sylibooking.gn
CSRF_TRUSTED_ORIGINS=https://api.sylibooking.gn
```

Generate the secret key with:

```bash
python -c "import secrets; print(secrets.token_urlsafe(64))"
```

**Never reuse the development one, and never commit it.** `SECRET_KEY` signs
sessions and password reset tokens; a leaked one is a way into every account.

### First deploy

Once it is up:

```bash
railway run python backend/manage.py createsuperuser
```

Then check `https://<your-app>.up.railway.app/api/health/ready/`. It names
each part it depends on, so a failure tells you *which* — database, cache or
storage — rather than just "unhealthy".

### A note on the free tier

Railway sleeps inactive services on some plans. A sleeping worker does not
run beat, so reminders stop and no-show sweeps stop. If bookings matter more
than the bill, that is the thing to pay for first.

---

## 1b. The two apps, as web services

Three services from one repository: the API, the merchant app and the
customer app. The apps are Flutter, so on Railway they are **web builds** —
Android remains how most people will use them, and `RELEASE.md` still governs
that. What a web build buys is a venue with a laptop and no wish to install
anything, and a link somebody can open before they trust you enough to
install an app.

### Add each service

Both use the same Dockerfile; which app they build is a variable.

1. **New service → GitHub repo**, same repository.
2. **Settings → Config as code**: `deploy/railway-web.json`
3. **Variables**, per service:

| Service | Variables |
|---|---|
| merchant-web | `APP=merchant_app`<br>`API_BASE_URL=https://<api-domain>/api` |
| customer-web | `APP=customer_app`<br>`API_BASE_URL=https://<api-domain>/api` |

`APP` and `API_BASE_URL` are **build arguments**. Railway passes service
variables to a Dockerfile build, and both are declared `ARG` — but check the
build log the first time: `APP` has no default, so a build that never
received it fails immediately and says so rather than quietly building the
wrong app.

**`API_BASE_URL` is baked in at compile time.** A web build has no emulator
fallback and no settings screen; wrong here is an app that loads and can do
nothing. Point it at the API service's domain, including `/api`.

### Then tell the API about them

The browser enforces same-origin; Android never did. Production reads an
explicit allowlist and fails closed, so until this is set every request from
either web app is refused:

```
CORS_ALLOWED_ORIGINS=https://merchant.sylibooking.gn,https://customer.sylibooking.gn
```

Railway's generated domains work too, and are what you will have first.

### What a visitor downloads

Measured on this build, not estimated:

| | Raw | Over the wire |
|---|---|---|
| `main.dart.js` | 8.1 MB | **1.5 MB** gzipped |
| CanvasKit wasm | 6.8 MB | ~2.5 MB, cached for a year |

The image pre-compresses everything at build time and nginx serves those
directly, so the first visit is roughly **4 MB** and every later one is
close to nothing.

That is a real number to weigh, and it points different ways for the two
apps. **For the merchant app it is clearly worth it**: a venue opens it once
at the start of a shift, on wifi, probably on a laptop, and never installs
anything. **For the customer app it deserves a thought** — 4 MB on mobile
data to browse venues, against a native app that downloads once. It is a
reasonable channel for somebody following a link who has not installed
anything, and a poor default for a regular. Both are built here; which you
promote is a product decision, not a technical one.

---

## 2. Cloudflare R2, for images

Uploads must not live on the container's disk: Railway replaces the container
on every deploy and takes the photos with it.

1. Cloudflare dashboard → **R2** → create a bucket, e.g. `sylibooking-media`.
2. **Manage R2 API Tokens** → create a token with **Object Read & Write**
   scoped to that bucket.
3. Note the **Account ID** — the S3 endpoint is
   `https://<account-id>.r2.cloudflarestorage.com`.
4. Give the bucket a public domain: **Settings → Public access → connect a
   domain** (e.g. `media.sylibooking.gn`). Without this the API endpoint is
   not publicly readable and every image 403s.

```
USE_S3_MEDIA=True
AWS_ACCESS_KEY_ID=<R2 access key>
AWS_SECRET_ACCESS_KEY=<R2 secret key>
AWS_STORAGE_BUCKET_NAME=sylibooking-media
AWS_S3_ENDPOINT_URL=https://<account-id>.r2.cloudflarestorage.com
MEDIA_CUSTOM_DOMAIN=media.sylibooking.gn
```

**Set these before the first real upload, not after.** Photos written to
container disk are gone at the next deploy, and the database rows that point
at them are not.

### After switching R2 on

```bash
railway run python backend/manage.py backfill_image_copies
```

Every picture uploaded before image derivatives existed serves its original
to every browse card until this has run. It is idempotent — safe to run twice,
useless if never run.

---

## 3. Redis, the worker and beat

Three services, one image. Reminders, no-show sweeps and payment polling all
live on the worker; without it the API still works and nothing scheduled ever
happens.

1. Add **Redis** to the Railway project. It sets `REDIS_URL`.
2. Add two more services from the same repo, changing only the start command:

| Service | Config as code | Also set |
|---|---|---|
| worker | `deploy/railway-worker.json` | `RUN_MIGRATIONS=no` |
| beat | `deploy/railway-beat.json` | `RUN_MIGRATIONS=no` |

Set **Settings → Config as code** to that path and the start command comes
with it — there is nothing to type into a dashboard field.

**Those two files declare no health check, and that is the point.** The root
`railway.json` checks `/api/health/`, and a service using it that serves no
HTTP fails every probe: the deploy is marked failed while the process it
started is running perfectly and logging tasks succeeding. Nothing about
that failure names the health check as the cause.

`RUN_MIGRATIONS=no` matters: the entrypoint migrates on boot, and three
services racing the same migration is how a half-applied schema happens. The
web service is the one that migrates.

3. On **all three** services (web, worker, beat):

```
CELERY_BROKER_URL=${{Redis.REDIS_URL}}
REDIS_URL=${{Redis.REDIS_URL}}
```

Railway's `${{Redis.REDIS_URL}}` syntax references the Redis service; using
it rather than pasting the URL means a rotated credential updates everywhere.

**Redis is not optional, and production refuses to boot without it.** The
cache holds two things that must be shared across workers:

* **Throttle counters.** Per-process, a limit of "5 an hour" silently becomes
  five an hour *per worker*.
* **In-flight Orange payment context.** The `pay_token` is written when a
  payment starts and read when its status is checked — different requests,
  different workers. A worker that cannot find it can never settle the
  payment, so the customer pays and the booking stays pending.

Setting `CELERY_BROKER_URL` satisfies this; `REDIS_URL` overrides it if you
want the cache on a different instance. Getting it wrong fails at boot with a
message naming the variable, rather than at midnight with a booking nobody
can confirm.

Exactly one beat service. Two produce every reminder twice.

---

## 4. SMS

Reset codes and reminders are generated, hashed, expiring and attempt-limited
today — they simply never leave the machine. This is the one integration that
makes the difference between a customer who can recover their account and one
who cannot.

### Choosing a gateway (decision D4, still open)

The adapter is **vendor-neutral on purpose**: every aggregator offers an HTTP
endpoint taking a destination and a body, so the URL, method, auth and field
names are all settings. Pick on price and on Guinean delivery rates, not on
what the code supports.

Set `SMS_NOTIFIER=accounts.gateways.HttpSmsNotifier`, then one of these
shapes.

**Twilio**

```
SMS_URL=https://api.twilio.com/2010-04-01/Accounts/<SID>/Messages.json
SMS_ENCODING=form
SMS_USERNAME=<Account SID>
SMS_PASSWORD=<Auth Token>
SMS_PAYLOAD={"To": "+{to}", "From": "<your Twilio number>", "Body": "{text}"}
```

**A generic reseller with an API key**

```
SMS_URL=https://gateway.example.gn/api/v1/send
SMS_HEADERS={"Authorization": "Bearer <key>"}
SMS_PAYLOAD={"to": "{to}", "from": "{sender}", "text": "{text}"}
SMS_SENDER=Sylibooking
SMS_SUCCESS_PATH=status
SMS_SUCCESS_VALUE=OK
```

`{to}`, `{text}` and `{sender}` are substituted anywhere they appear in the
payload, at any depth.

**Set `SMS_SUCCESS_PATH` if your gateway answers 200 with a failure in the
body.** Plenty do. Without it, an undelivered message reads as delivered, and
a reminder nobody received is the one failure this product cannot otherwise
see.

Numbers are normalised to digits with the country code and no `+`. If your
gateway wants a leading `+`, put it in the payload template as `+{to}`, as in
the Twilio example.

---

## 5. Orange Money

### What to get

1. Register at [developer.orange.com](https://developer.orange.com).
2. Subscribe to **Orange Money Web Payment** for **Guinea**.
3. From your application you get a **client id** and **client secret**;
   from the merchant agreement you get a **merchant key**.
4. Orange issues sandbox credentials first. Do not skip that stage.

### Variables

```
ORANGE_MONEY_ADAPTER=payments.orange.OrangeMoneyProvider
ORANGE_CLIENT_ID=<client id>
ORANGE_CLIENT_SECRET=<client secret>
ORANGE_MERCHANT_KEY=<merchant key>
ORANGE_CURRENCY=GNF
ORANGE_RETURN_URL=https://<your-app>.up.railway.app/payment/done
ORANGE_CANCEL_URL=https://<your-app>.up.railway.app/payment/cancelled
ORANGE_NOTIF_URL=https://<your-app>.up.railway.app/api/payments/callbacks/orange/<secret>/
ORANGE_CALLBACK_SECRET=<the same secret as in that URL>
```

Generate the callback secret the same way as `SECRET_KEY`. **An unset
`ORANGE_CALLBACK_SECRET` refuses every callback rather than accepting every
callback** — that is deliberate, and there is a test for it.

### Check these against your contract

The defaults are the published shape, and the published shape is not always
your shape. When the credentials arrive, confirm:

```
ORANGE_TOKEN_URL     default https://api.orange.com/oauth/v3/token
ORANGE_PAYMENT_URL   default .../orange-money-webpay/dev/v1/webpayment
ORANGE_STATUS_URL    default .../orange-money-webpay/dev/v1/transactionstatus
```

`dev` in those paths is the sandbox. Production is a different path segment —
Orange tells you which. **Change the variable, not the file.**

### Refunds

Orange Money Web Payment has no refund endpoint. The adapter says so out loud
rather than reporting a success nobody asked anybody for. A merchant refunding
a deposit does it from the Orange merchant portal, and records it here.

---

## 6. MTN Mobile Money

### What to get

1. Register at [momodeveloper.mtn.com](https://momodeveloper.mtn.com).
2. Subscribe to **Collections**. Note the **primary subscription key**.
3. In sandbox, create an API user and key (MTN's provisioning endpoints, once
   per environment). Production credentials come from your MTN Guinea
   agreement.
4. Subscribe to **Disbursements** as well **only if you want refunds through
   the API** — it is a separate product with its own key, and collections
   work without it.

```
MTN_MONEY_ADAPTER=payments.mtn.MtnMoneyProvider
MTN_BASE_URL=https://sandbox.momodeveloper.mtn.com
MTN_API_USER=<api user uuid>
MTN_API_KEY=<api key>
MTN_SUBSCRIPTION_KEY=<primary subscription key>
MTN_ENVIRONMENT=sandbox
MTN_CURRENCY=EUR
MTN_CALLBACK_SECRET=<generated>
MTN_DISBURSEMENT_SUBSCRIPTION_KEY=<only if you want API refunds>
```

**`MTN_CURRENCY=EUR` in sandbox is not a mistake.** MTN's sandbox only settles
in EUR; production Guinea is `GNF`. Getting this wrong produces a refusal
whose message does not mention currency.

`MTN_ENVIRONMENT` is `sandbox` until MTN issues your production environment
string (for Guinea it is usually `mtnguinea`) — it is part of your contract,
not something to guess.

---

## 7. Firebase push

The backend has been ready since Slice 7. The client half is built and
defaults to a no-op, so **an app with no Firebase project runs perfectly and
simply is not pushed to**. That is why this step can wait.

### Console

1. [console.firebase.google.com](https://console.firebase.google.com) → new
   project.
2. Add **two Android apps**, one per package:
   - `com.sylibooking.merchant_app`
   - `com.sylibooking.customer_app`
3. Download each `google-services.json` and put it at:
   - `apps/merchant_app/android/app/google-services.json`
   - `apps/customer_app/android/app/google-services.json`
4. **Project settings → Service accounts → Generate new private key.** That
   JSON is what the *server* uses.

### Server

```
PUSH_SENDER=notifications.push.FirebasePushSender
GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json
```

On Railway, add the service account JSON as a file via a volume, or paste its
contents into a variable and write it out in `entrypoint.sh`. **Do not commit
it** — it can send push to every device you have.

### Apps

**The code is already wired.** Both apps build a `FirebasePushRegistrar` in
`main()`, it works out its own platform, and it disables itself when there is
no Firebase project — so a build without `google-services.json` runs
perfectly and simply is not pushed to. What is left is the Android plumbing
that file needs.

**The Gradle plugin is applied in both apps too** — declared in
`android/settings.gradle.kts`, applied in `android/app/build.gradle.kts`.
Verified by building both APKs: the plugin reads the JSON and generates
`google_app_id`, `project_id` and `google_api_key` into the build.

So the only thing a machine needs is the file itself.

### google-services.json is not in the repository

It is git-ignored, per app. Google does not treat it as a secret — it is
compiled into the APK and anyone can read it out of one — but this
repository is public, and publishing a project id and an API key invites
scanners for no benefit.

The consequence is real and worth knowing: **a fresh clone cannot build the
Android apps.** Gradle fails with a message about a missing
`google-services.json`. Anyone building them needs to download both from
console.firebase.google.com first, into:

```
apps/merchant_app/android/app/google-services.json
apps/customer_app/android/app/google-services.json
```

CI does not build Android — it runs `flutter test` and `flutter analyze`,
neither of which touches Gradle — so this does not affect the pipeline.

The file that must **never** be committed under any circumstances is the
service account key from *Project settings → Service accounts*. That one can
push to every device you have.

### Web push is a separate job

Both apps are also deployed as web services, and web push is not covered by
the above. It needs a `firebase-messaging-sw.js` service worker and the
Firebase JS config in each app's `web/` directory, neither of which
`google-services.json` provides.

Until that is done the web builds behave exactly as an unconfigured Android
build does: everything works, `Firebase.initializeApp` fails, the failure is
caught, and no push arrives. Nothing breaks — the feature is simply absent.

Worth deciding rather than assuming: a merchant on a laptop is arguably the
person who most wants an alert, and they are the likeliest web user.

---

## 8. WhatsApp (optional)

Some venues would rather have WhatsApp than SMS, and it costs less per
message. It is last because it needs a business verification that takes days.

1. [developers.facebook.com](https://developers.facebook.com) → new app →
   **WhatsApp**.
2. Add a phone number and verify the business.
3. **Create and submit a message template** for booking reminders. Approval
   takes a day or two.

```
WHATSAPP_NOTIFIER=accounts.gateways.WhatsAppNotifier
WHATSAPP_PHONE_NUMBER_ID=<from the console>
WHATSAPP_TOKEN=<permanent access token>
WHATSAPP_TEMPLATE=<your approved template name>
WHATSAPP_LANGUAGE=fr
```

**Only templates work.** WhatsApp allows free-form messages solely inside a
24-hour window after the customer writes to *you*, and every message this
product sends is outside one by definition. The adapter refuses rather than
sending something Meta would silently drop.

The template needs exactly one body parameter — the sentence the product has
already composed. A template with more placeholders needs the adapter changed
to fill them.

---

## Turning things on safely

Every switch above is one variable, so every switch is reversible in one
variable. When you enable a payment provider:

1. Enable it in **sandbox** first, with `MTN_ENVIRONMENT=sandbox` or Orange's
   `dev` path.
2. Make one real booking end to end and watch `/api/metrics/` —
   `payments.completion_rate` is the number that says whether money that
   starts also finishes.
3. Only then move to production credentials, and expect the currency and the
   environment string to change with them.

If a provider misbehaves, set its adapter back to
`payments.providers.MockPaymentProvider`. Bookings keep working on cash on
arrival, which is what most venues do anyway.

---

## What is still not built

Honest list, so nothing here is a surprise later.

- **Reconciliation against a provider's ledger** (plan Slice 31). Refunds and
  the payments dashboard exist; a daily job comparing our rows against theirs
  does not. Until it does, a disagreement is found by a merchant rather than
  by us.
- **iOS**. Both apps are Android-only today. Firebase, the stores and the
  signing story all differ.
- **Deep links** (Slice 39), so the link in a reminder opens the booking.
- **A third language** (Slice 37). English and French are complete.

---

## Where the secrets live

Nothing in this document belongs in the repository. For each of the values
above, the rule is the same: environment variable on Railway, never a file in
git, and **`android/key.properties` and the upload keystore stay git-ignored
forever** — losing that key means never updating an installed app again. See
[`RELEASE.md`](RELEASE.md).
