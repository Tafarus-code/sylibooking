# Sylibooking — Platform Assessment

**As of 12 August 2026** · branch `dev` at `fcffcf7` · assessed against the
working tree, not the plan.

This is a full audit of both apps and the backend: what is built, what is
half-built, what is missing, and what should change. Every claim below was
checked against code that was read or a command that was run in this session —
where something was verified by execution, the evidence is quoted.

It supersedes `PROJECT_STATUS.md`, which is dated 2 August and is now
materially wrong (see §2).

**Legend**

| Mark | Meaning |
|---|---|
| ✅ | Built, tested, working end to end |
| 🟡 | Built and working, but stubbed or with a known gap |
| 🔶 | Backend exists, no interface — admin or curl only |
| ⛔ | Blocked on something outside the repository |
| ❌ | Not started |

---

## 1. Verdict

The platform is **feature-complete for a pilot except for the three things that
take real money, real messages and real push** — and all three are blocked on
credentials rather than on engineering. The reservation spine, the kitchen, the
merchant back office and the customer journey are all built, tested and running.

What stands between this and a Conakry pilot is no longer code the team has to
design. It is: an Orange Money sandbox, an SMS aggregator contract, a Firebase
project, and one red test.

**Measured this session**

| Metric | Value |
|---|---|
| Python (excl. migrations) | 20,970 lines |
| Dart (`lib/`, excl. generated l10n) | 19,378 lines |
| Dart tests | 12,884 lines |
| Django models | 16 |
| API routes | 61 |
| Backend tests | **786 pass**, 1 skipped |
| `shared_client` tests | **117 pass** |
| Customer app tests | **248 pass** |
| Merchant app tests | **276 pass, 1 fail** ← see §7.1 |
| Localisation keys | 392 customer / 513 merchant, EN + FR |
| TODO / FIXME / HACK markers | **0** |

Total: **1,428 automated tests** (786 + 117 + 248 + 277), one of them failing.

---

## 2. `PROJECT_STATUS.md` is stale and should be retired

That document's §11 lists ten things "to improve, in order". **Eight of the ten
have since shipped.** Anyone planning from it today would rebuild work that
already exists.

| `PROJECT_STATUS.md` said | Reality on `dev` today |
|---|---|
| "No `Space` create/update/delete endpoint — *blocking*" | ✅ `MerchantSpacesView` + `MerchantSpaceItemView`, and `spaces_screen.dart` |
| "A merchant cannot register their own venue" | ✅ `create_venue_screen.dart` |
| "Reservations never complete — nothing sets it" | ✅ `complete` action sets `arrived_at` (`api/views.py:325`) |
| "Deposits are taken but never consumed" | ✅ `refund` action + `sweep_no_shows` beat task |
| "Reviews cannot be moderated" | ✅ `MerchantReviewsView` + `MerchantReviewFlagView`, `reviews_screen.dart` |
| "No walk-in orders" | ✅ `MerchantWalkInOrderView`, `walk_in_order_screen.dart` |
| "No Celery, no Redis, no scheduled work of any kind" | ✅ Celery + beat, three periodic tasks |
| "No pagination in the merchant app" | ✅ paginated desk and queue |
| "No observability" | ✅ health, readiness, metrics, structured logs, crash reporting |
| "No deployment — it runs on a laptop" | ✅ Dockerfile, compose (redis/db/web/worker/beat), `render.yaml` |

Still open from that list: **real payment providers** and **merchant analytics**.

**Recommendation:** replace `PROJECT_STATUS.md` with this file, or reduce it to
a pointer. Two status documents that disagree is worse than one that is late.

---

## 3. Backend — Django + DRF

### 3.1 Data model ✅ — 16 models

| App | Models |
|---|---|
| `establishments` | `Establishment`, `Space`, `OpeningHours`, `MenuItem`, `MerchantMembership`, `Review`, `Photo`, `Favourite` |
| `reservations` | `Reservation` |
| `orders` | `Order`, `OrderItem` |
| `payments` | `Payment` |
| `accounts` | `CustomerProfile`, `PasswordResetCode` |
| `notifications` | `Notification`, `DeviceToken` |

The architectural decisions from the brief have held up:

- `Establishment.type` stayed a plain field. Restaurant-only ordering is a
  validation rule in `orders/rules.py`, with a comment stating outright that it
  is "a product decision made this month, not a truth about the data" and is one
  line to change. That is the right shape.
- The UUID `reference` as the credential is what makes accounts genuinely
  optional — the whole customer app works signed out.
- `MerchantMembership` carries the role, so one person can work several venues
  at different levels.

### 3.2 Reservation lifecycle ✅ — now closed

The gap that mattered most in the previous audit is gone. `ReservationViewSet`
exposes `confirm`, `complete`, `refund`, `cancel`; `complete` stamps
`arrived_at`; `lapse_no_shows` and the `sweep-no-shows` beat task (every 600s)
handle the guest who never came. A deposit now has a defined fate.

### 3.3 Asynchronous work ✅

Celery with a beat schedule, three periodic tasks:

| Task | Interval | Purpose |
|---|---|---|
| `queue_due_reminders` | 300s | booking reminders |
| `sweep_no_shows` | 600s | lapse bookings nobody showed for |
| `poll_pending_payments` | 30s | chase payment state without a watcher |

`notifications/tasks.py` documents two rules worth keeping: a task takes ids not
objects, and a task that cannot do its job raises rather than swallowing. The
reminder logic (`reminders.py`) refuses to fire inside quiet hours — a 09:00
booking does not ring a phone at 06:00. That is a market-appropriate detail.

### 3.4 Security and abuse surface ✅

Well beyond what an MVP usually carries:

- Ten named throttle scopes (`login_ip`, `login_username`, `register`,
  `password_reset_identifier`, `booking_phone`, …), not one blanket rate.
- `SECRET_KEY` required from config, `DEBUG` off by default, HSTS, SSL redirect,
  secure cookies, `CORS_ALLOW_ALL_ORIGINS` false in production, CSRF trusted
  origins configurable.
- Reset codes are hashed, 15-minute lifetime, 5-attempt cap, and issuing a new
  one invalidates the old.
- Account closure exists with a documented policy — "the person goes, the
  venue's books stay".

The throttle rates are explicitly provisional; §9 covers what to do now that
metrics exist.

### 3.5 Internationalisation ✅

`LocaleMiddleware`, a hand-written French catalogue, and a pure-Python `.po` →
`.mo` compiler (`manage.py compile_po`) written because there is no gettext
toolchain here or in CI. Statuses carry `msgctxt` contexts because "Completed"
is three different words in French depending on whether it describes a payment,
a sitting or an order. A test asserts the `.mo` is committed and in step with
the `.po`.

---

## 4. Customer app — 16 screens ✅

| Feature | Status | Note |
|---|---|---|
| Browse: photos, open/closed, distance, search | ✅ | Server-side filtering |
| Places / Dishes feed toggle | ✅ | Dishes feed via `FeaturedItemsView` |
| Venue detail behind four tabs | ✅ | Hours, menu, photos, reviews |
| Full-screen photo viewer | ✅ | Deliberately dark chrome |
| Availability by date and party size | ✅ | |
| Book a table (pay on arrival) | ✅ | |
| Pay by mobile money | 🟡 | Real flow, mock provider |
| Deposit explained in words | ✅ | `deposit_disclosure.dart` |
| My bookings + cancel | ✅ | Reference-keyed, no account needed |
| Order ahead, cart, checkout, tracking | ✅ | Restaurants only, enforced server-side |
| Order attached to a booking | ✅ | `reservationReference` flows to checkout |
| Favourites | ✅ | Local first, merged on sign-in |
| Optional account + claim history | ✅ | Verified live this session |
| Profile edit + account closure | ✅ | |
| Password reset by SMS or email | 🟡 | Codes real, delivery is console |
| Write a review | ✅ | Server checks the visit happened |
| Get directions | ✅ | Hands off to a maps app |
| EN / FR toggle | ✅ | 392 keys |
| Per-venue branding | ✅ | Scoped to venue screens |

**Absent:** push notifications (§7.3), offline cache, deep links, receipt or
invoice export, map view of results.

---

## 5. Merchant app — 19 screens ✅

| Feature | Status | Note |
|---|---|---|
| Login, token session, restore | ✅ | |
| Venue picker for multi-venue accounts | ✅ | Hidden for single-venue users |
| Desk: today / next 7 days, split pane on tablet | ✅ | 44% list + detail pane |
| Confirm / cancel / **mark arrived** | ✅ | Refuses to confirm unpaid mobile money, and says why |
| Kitchen queue grouped by stage | ✅ | Placed → preparing → ready → collected |
| Walk-in order at the counter | ✅ | Built for one hand and a queue |
| Payments dashboard | ✅ | Collected, awaiting, failed, who to chase |
| Reviews with rating distribution + flag | ✅ | |
| Spaces (tables/rooms) CRUD | ✅ | Grouped by kind; retired spaces read as retired |
| Create a venue | ✅ | Four fields, the rest later |
| Menu CRUD, sold-out, item pictures | ✅ | Staff may mark sold out; owners/managers edit |
| Photos from camera or gallery | ✅ | |
| Opening hours incl. past midnight | ✅ | Saved as a week |
| Branding: five presets, live preview | ✅ | Contrast-checked, no free-form picker |
| Staff add / re-role / remove | ✅ | Owner only; server refuses to orphan a venue |
| Pagination on desk and queue | ✅ | |
| Role gating throughout | ✅ | Entries a role cannot use are absent, not refused |
| EN / FR toggle | ✅ | 513 keys |

**Absent:** analytics beyond payments, printed kitchen tickets, shift
scheduling, export of anything, push alerts for new bookings.

---

## 6. Infrastructure ✅

- **CI:** six jobs — ruff, Django on SQLite, Django on PostgreSQL with
  `makemigrations --check`, and analyze + test for each of the three Flutter
  packages, with `--fatal-infos`.
- **Containers:** Dockerfile, `docker-compose.yml` running redis, db, web,
  worker and beat, plus `deploy/render.yaml` and `entrypoint.sh`.
- **Media:** correctly refuses to keep uploads on container disk —
  `USE_S3_MEDIA` with Cloudflare R2 documented, and the reasoning (no egress
  charge) recorded in `deploy/README.md`.
- **Release:** real signing config and a documented process in `RELEASE.md`.
- **Seed data:** `manage.py seed_demo` — 22 venues across Conakry and Labé,
  idempotent, fixed seed. Extended this session with customer accounts (§10).

---

## 7. Defects found

Ordered by consequence. Each was reproduced.

### 7.1 A test that fails for nineteen hours of every day ⛔ *fix first*

`apps/merchant_app/test/widget_test.dart:5721` — *"staff can still work the
day"* — expects a **Mark arrived** button and finds none:

```
Expected: at least one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Mark arrived": []>
```

The cause is a collision between two correct pieces of code:

- The fixture books **today at 19:00** — `booking()`, `widget_test.dart:146-147`:
  `DateTime(now.year, now.month, now.day, 19)`.
- The button only appears once the sitting has begun —
  `reservation_card.dart:51-52`: `canComplete = status.isOpen &&
  reservation.dateTime.isBefore(DateTime.now())`, with the comment "nobody has
  arrived for a table that is not due yet".

So the test passes only when the suite runs between 19:00 and midnight local
time. It failed here at 01:02.

**This makes CI unreliable, not just this test.** `.github/workflows/ci.yml`
runs `ubuntu-latest` with no `TZ` set, so the runner is UTC and the merchant
Flutter job fails on **any push before 19:00 UTC**. A pipeline that is normally
red teaches everyone to ignore red.

**Fix:** the fixture needs a booking already under way for the completable case —
`now.subtract(const Duration(hours: 1))` — rather than a fixed clock hour. The
repo has met this class of bug before; commit `Stop the queue pagination tests
failing after 23:30 in Conakry` fixed the same shape elsewhere. Worth a sweep
for other fixed-hour fixtures.

### 7.2 No request timeouts anywhere in the Dart client 🟡

`grep '\.timeout('` across `shared_client/lib`, `customer_app/lib` and
`merchant_app/lib` returns **nothing**. `package:http` has no default timeout,
so a stalled connection — the normal failure mode on a mobile network in
Conakry, rather than a clean refusal — leaves a spinner turning indefinitely
with no error and no retry.

For a product whose users are on intermittent mobile data, this is the single
most user-visible robustness gap. Wanted: a default timeout in
`SylibookingApi`, a distinct "the network is slow" message, and a retry on the
idempotent reads.

### 7.3 Push notifications are half-wired 🔶

The server half is complete and tested: `DeviceToken`, `POST /api/devices/`,
`FirebasePushSender` behind a `PUSH_SENDER` setting, `ConsolePushSender` as the
default that keeps the code path exercised.

The client half does not exist. Neither `pubspec.yaml` carries a Firebase
dependency, and nothing in either app calls the device-registration endpoint.
`venue_desk_screen.dart:46` says as much: *"Until push notifications exist —
they need Firebase and a signing…"*. The merchant still learns about a booking
by pulling to refresh.

Blocked on a Firebase project, but note the backend is ready and waiting.

### 7.4 Docstrings that contradict shipped features 🟡

- `customer_app/lib/src/screens/my_bookings_screen.dart` — *"There are no
  customer accounts yet, so the ids come from local storage"*. Accounts shipped
  in Slice 18; the screen reads history from the account.
- `customer_app/lib/src/screens/booking_form_screen.dart` — *"Payment is on
  arrival in the MVP"*. Mobile money has worked since Slice 5.

In a codebase this well commented, a comment is treated as true. These two are
not, and they sit on the customer app's two most-edited screens.

### 7.5 No image resizing or thumbnails 🟡

Uploads are stored and served at original resolution — no thumbnailing in
`establishments/models.py` or the serializers. The browse list requests a
full-size JPEG per venue card. On mobile data this is the difference between a
list that paints and a list that crawls. Storage is correctly on R2; the
transfer size is the problem, not the location.

### 7.6 `main` is 113 commits behind `dev`, and has diverged

`main` was promoted once — *"Promote dev to main: working MVP reservation
loop"*, 27 July. Since then:

```
git rev-list --count main..dev  → 113
git rev-list --count dev..main  → 2
```

So `main` is 113 commits behind **and** carries 2 commits that are not on `dev`.
The divergence is the part worth attention: whatever those two are, they will
have to be reconciled at the next promotion rather than fast-forwarded. Every
slice from 1 to 22 — the entire feature set described in this document — exists
on `dev` only, while the release process built in Slice 22 targets `main`.

---

## 8. Missing features

### 8.1 Blocked on something outside the repository ⛔

These are not engineering problems. Each needs the user to obtain something.

| Feature | Blocked on | Backend readiness |
|---|---|---|
| Orange Money | Sandbox credentials + API docs | Interface, deposit, polling, refund all built; `PAYMENT_PROVIDERS` maps to the mock |
| MTN Mobile Money | Same | Same |
| Payment reconciliation | Depends on the two above | `refund` action exists |
| SMS that leaves the machine | Choice of aggregator (decision D4) | `NOTIFIERS['sms']` is one setting away |
| Push delivery | A Firebase project + service account | `FirebasePushSender` written; clients not (§7.3) |

`payments/providers.py` keeps `MockPaymentProvider` behind the same ABC as a
real one, so switching is a settings change. That claim was verified — the mock
implements `initiate_payment`, `check_status` **and** `refund`.

### 8.2 Not started — beyond the MVP ❌

From the market report's later phases, none of this exists and none of it is
urgent:

- **Loyalty / repeat-customer rewards.** The data to build it is already there
  (completed reservations per customer); nothing reads it that way.
- **Inventory / stock.** Menu items have `is_available` and nothing behind it.
- **Printed kitchen tickets.** The queue is on screen only.
- **WhatsApp fallback.** Named in the brief as a channel for venues that will
  not install an app. Nothing exists.
- **Merchant analytics.** Covers per night, turnover, popular dishes, no-show
  rate, repeat customers. The payments dashboard is the only reporting.
- **Local languages.** EN and FR only. Susu, Pular and Malinké are how a large
  share of this market actually reads. The i18n machinery is already built and
  proven with two catalogues — adding a third is catalogue work, not code.

### 8.3 Product gaps worth deciding on

- **Offline behaviour.** Favourites are optimistic and offline-tolerant; nothing
  else is. A merchant on the floor with no signal cannot see tonight's list.
- **Deep links.** A booking confirmation cannot be reopened from an SMS link —
  which matters more once SMS actually sends.
- **Receipts.** No customer-facing receipt or invoice artefact.
- **Map view.** Distance is shown and sortable; venues are never plotted.

---

## 9. Improvements to what already exists

Ordered by value per unit of effort.

1. **Tune the throttle rates.** They were set loose on purpose and explicitly
   deferred until throttle-hit metrics existed. Slice 20 built those metrics.
   This is now unblocked and is a config change.
2. **Timeouts + retry in `SylibookingApi`** (§7.2). Small, central, high impact.
3. **Serve resized images** (§7.5). One dependency and an upload hook.
4. **Merchant analytics.** The highest-value *new* merchant feature, and every
   number it needs is already in the database. Covers per night and no-show rate
   are queries, not new plumbing.
5. **Client-side push** once Firebase exists (§7.3) — the backend is done.
6. **A third language.** Cheap given the machinery, and a genuine differentiator
   in Conakry.
7. **Merge `dev` into `main`** and make the release process real (§7.6).

---

## 10. Changes made in this session

Recorded so the diff is not a mystery:

- **`backend/establishments/management/commands/seed_demo.py`** — added customer
  account seeding. Four accounts, one per contact-details case (phone+email,
  phone only, email only, neither), each with favourites, a booking in every
  state the Bookings tab groups by, a completed and an in-flight order, and a
  review on a past visit. Bookings are created fresh rather than reassigned from
  the existing crowd, so no merchant's list changes under them. Idempotent —
  verified by running it twice with no new rows on the second pass.
  Before this, the customer app's entire signed-in half seeded empty.
- The report block now lists restaurants and lounges separately, because only
  restaurants have a kitchen queue.
- An `admin` superuser was created for the Django admin.

Backend suite re-run after the change: **786 pass**.

Pre-existing uncommitted work in the tree, untouched by me:
`reservations_screen.dart` (a `LayoutBuilder` fix so the empty-desk message is
measured against its pane rather than the window) and the matching tests in
`widget_test.dart`. Those three tests pass.

---

## 11. Credentials for testing

All seeded accounts share the password **`sylibooking`**.

| Kind | Usernames |
|---|---|
| Merchant — restaurants (kitchen queue) | `ledamier`, `chezmariama`, `lebaobabdore`, `terrassedunige`, `maquiskaloum`, `lapaillote`, `saveursdufouta`, `lepetitmarche`, `rizsauce`, `chezsory`, `lewharf` |
| Merchant — lounges (no orders, by rule) | `lepetitbaobab`, `skyloungekipe`, `lenimba`, `villa224`, `lecocotier`, `bissaplounge`, `laterrassedixi`, `nuitblanche`, `lesalonrouge`, `kaloumnights`, `lehangar` |
| Per venue, also | `<venue>.mgr` (manager), `<venue>.staff` (staff) |
| Customer | `mariama`, `sekou`, `kadiatou`, `binta` |
| Django admin | `admin` |

To exercise the kitchen, log in as a **restaurant** — `chezmariama` has five
open orders. A lounge has none, and that is the rule working, not a bug.

Five accounts predate the seed (`amadou`, `ibrahima`, `aissatou` on Le Petit
Baobab, `fatou` on Chez Fatou, and `tafarus`). Their passwords are hashed and
cannot be recovered; they were left untouched rather than reset.

---

## 12. Risk register

| Risk | Severity | Note |
|---|---|---|
| CI red most of the day (§7.1) | **High** | Erodes trust in the pipeline; masks the next real failure |
| No payment provider | **High** | Blocked externally; the pilot cannot take money |
| No request timeouts (§7.2) | **Medium** | Presents as "the app is frozen" on exactly the network this market has |
| Push undelivered (§7.3) | **Medium** | Merchants must remember to refresh |
| Two disagreeing status docs (§2) | **Medium** | Already caused stale planning |
| Image weight (§7.5) | **Medium** | First impression of the customer app on mobile data |
| Throttle rates unproven | **Low** | Loose by design; metrics now exist to tighten them |
| `main` diverged from `dev` | **Low** | 113 behind, 2 ahead — reconcile before the next promotion |

---

## 13. Honest summary

Ten days ago the blocking gaps were that a merchant could not create a venue,
could not enter a table, and nothing ever completed a booking. **All three are
fixed**, along with reviews, walk-ins, pagination, deposits, the async layer,
observability, containers and a release process. That is a substantial amount of
real work, and the test suite grew with it rather than after it.

The quality signals are good and not superficial: zero TODO markers in 40,000
lines, comments that explain *why* rather than *what*, business rules that state
their own reversibility, and 1,428 tests concentrated on the logic that would
hurt most if it broke.

The distance to a pilot is now four external dependencies and one red test — not
a backlog. The most useful engineering work available today is the unglamorous
kind: fix the clock-dependent test, put timeouts on the network layer, shrink
the images, and give merchants numbers about their own business.
