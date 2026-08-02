# Sylibooking — Project Status

**As of 2 August 2026** · branch `dev` at `b7e7084` · 62 commits over 7 days
(26 July – 1 August 2026).

This is an audit of what actually exists in the repository, read from the code
rather than from the plan. Where something is half-built or stubbed, it says so
and says exactly where the edge is.

**Legend**

| Mark | Meaning |
|---|---|
| ✅ | Built, tested, and working end to end against the real backend |
| 🟡 | Built and working, but deliberately stubbed or with a known gap |
| 🔶 | Backend exists, no interface — reachable only via Django admin or curl |
| ❌ | Not started |

---

## 1. At a glance

| Area | Status | Note |
|---|---|---|
| Django data model | ✅ | 14 models, migrations clean on SQLite and PostgreSQL |
| REST API | ✅ | ~35 routes, membership-checked, 476 tests |
| Customer app | ✅ | Browse → book → order → track, end to end |
| Merchant app | ✅ | Desk, kitchen queue, payments, venue management |
| English / French | ✅ | Both apps and the API, with a toggle in each |
| Payments | 🟡 | Mock provider only; no Orange Money or MTN |
| SMS | 🟡 | Console stub; nothing leaves the machine |
| Tables and rooms (`Space`) | 🔶 | No create/edit endpoint at all — admin only |
| Venue self-registration | 🔶 | API + client method exist, no screen calls them |
| Review moderation | 🔶 | `is_hidden` field exists, nothing can set it |
| Reservation completion | ❌ | Nothing ever moves a booking to `completed` |
| No-show / deposit forfeiture | ❌ | Deposit is taken, nothing consumes it |
| Reminders and notifications | ❌ | No Celery, no Redis, no scheduled work of any kind |
| Loyalty, inventory, WhatsApp, analytics | ❌ | Phase 3+ in the plan, untouched |

**Size:** 12,651 lines of Python (excluding migrations), 14,943 lines of Dart
(excluding generated localisations), 8,351 lines of Dart tests.

**Tests:** 911 total — 476 backend, 202 customer app, 137 merchant app, 96
shared package. Six CI jobs, all green on `dev`.

---

## 2. Where this sits against the MVP in CLAUDE.md

The brief defines the MVP as one flow, end to end:

| # | MVP step | Status |
|---|---|---|
| 1 | Merchant registers an establishment, **adds tables/rooms**, sets opening hours | 🔶 **Partly.** Hours ✅. Registering a venue and adding tables/rooms are admin-only. |
| 2 | Customer browses and sees real availability for a date/time | ✅ |
| 3 | Customer books a slot, pay-on-arrival | ✅ (mobile money also works, against the mock) |
| 4 | Merchant sees the reservation and can confirm or cancel | ✅ |

**The loop closes**, and a good deal beyond it has been built — ordering ahead,
reviews, photos, favourites, optional accounts, per-venue branding, a payments
dashboard, full French. But step 1 has a hole in it: a merchant cannot create
their own venue or define a single table from inside the app. Every demo so far
has worked because `seed_demo` created those rows directly.

This is the single most important gap in the project. Everything else on the
"missing" list is a later phase; this one is inside the MVP as written.

---

## 3. Backend — Django + DRF

### 3.1 Data model ✅

Fourteen models across six apps. All migrations apply cleanly to a fresh
database (CI verifies this against PostgreSQL on every push).

| App | Models |
|---|---|
| `establishments` | `Establishment`, `Space`, `OpeningHours`, `MenuItem`, `MerchantMembership`, `Review`, `Photo`, `Favourite` |
| `reservations` | `Reservation` |
| `orders` | `Order`, `OrderItem` |
| `payments` | `Payment` |
| `accounts` | `CustomerProfile`, `PasswordResetCode` |

Decisions worth recording:

- **`Establishment.type` is a plain field** (`lounge` / `restaurant`), not a
  fork in the model, exactly as the brief asked. Restaurant-only behaviour —
  ordering ahead — is enforced as a *validation rule* in `orders/rules.py`,
  not as a schema difference.
- **`MerchantMembership` is a through-model carrying a role** (owner / manager
  / staff), so one account can work several venues at different levels.
- **A reservation's `reference` is a UUID and is the credential.** An
  account-less customer proves ownership of a booking or order by holding an
  unguessable reference. This is what makes optional accounts possible.
- **`Order.reservation` is nullable** — an order can hang off a table booking
  or stand alone as a pickup.

### 3.2 API ✅

Roughly 35 routes. Public browse and booking, reference-keyed customer routes,
token-authenticated merchant routes that check membership on *every* handler.

- **Public:** establishments list/detail, availability for a date, create
  reservation, reviews, photos, theme presets.
- **By reference:** fetch a booking, cancel it, check payment status, fetch an
  order.
- **Optional account:** register, me, claim (attach this phone's bookings to a
  new account), history, favourites, password reset request + confirm.
- **Merchant:** login/logout/me, venues, venue profile, hours, menu CRUD, menu
  availability, staff CRUD, photos, orders queue, order status, payments
  dashboard.

### 3.3 Business logic ✅

Two engines carry the real complexity, and both are well covered:

- `reservations/availability.py` — slot generation, clash detection,
  double-booking prevention. Treats `pending`, `confirmed` *and* `completed` as
  holding a slot, so a merchant cannot accidentally book over a sitting.
- `establishments/hours.py` — opening hours including **past-midnight closing**
  (a lounge open until 04:00 is open, not closed), "open now", today's hours,
  the week's schedule.

### 3.4 Internationalisation ✅

- `LocaleMiddleware` + `Accept-Language`; both apps send the header.
- A hand-written French catalogue, compiled and committed.
- `manage.py compile_po` — a small pure-Python `.po` → `.mo` compiler, written
  because there is no GNU gettext toolchain on this machine or in CI. Supports
  `msgctxt`; refuses plurals rather than guessing.
- Statuses carry **contexts**, because "Completed" is a settled payment, a
  finished sitting and a collected order, and French wants a different word for
  each.
- A test asserts the `.mo` is committed *and* in step with the `.po`, since a
  `.po` edited without recompiling fails silently.

### 3.5 Test coverage ✅

476 tests. The heaviest files are the ones that should be:

| Tests | Area |
|---|---|
| 55 | Merchant roles and access control |
| 46 | Reviews and photos |
| 38 | Core API (browse, availability, booking) |
| 38 | Ordering ahead |
| 29 | Branding |
| 27 | Opening hours (incl. past midnight) |
| 27 | Customer accounts |
| 26 | Payments |
| 26 | Password reset |
| 24 | Payments dashboard |

---

## 4. Customer app — Flutter ✅

24 screens and widgets. Everything below is working against the live backend
and covered by widget tests at 360×900, 834×1112, 1440×900 and 900×360.

| Feature | Status | Note |
|---|---|---|
| Browse with photos, open/closed, distance | ✅ | Server-side search and filters |
| Filter by type, city, open-now | ✅ | |
| Venue detail: hours, menu cards, photos, reviews | ✅ | |
| Full-screen photo viewer, next/previous | ✅ | |
| Availability for a date and party size | ✅ | Dropdown day picker, not a sideways strip |
| Book a table | ✅ | Pay on arrival |
| Pay by mobile money | 🟡 | Works end to end **against the mock** |
| My bookings, cancel a booking | ✅ | Keyed by reference, no account needed |
| Order ahead (pickup / pre-order) | ✅ | Restaurants only, enforced server-side |
| Cart, checkout, order tracking | ✅ | Horizontal stage indicator |
| Favourites | ✅ | Local, merged into an account on sign-in |
| Optional account, claim history | ✅ | Nothing in the booking flow requires one |
| Write a review | ✅ | Tied to a real visit |
| Password reset by SMS or email | 🟡 | Code is real; delivery is a console stub |
| English / French toggle | ✅ | 226 keys, both catalogues complete |
| Get directions | ✅ | Hands off to a maps app |
| Per-venue branding | ✅ | Scoped to venue screens, never global |

**Not present:** push notifications, offline cache, deep links, in-app receipt
or invoice, order history export, account deletion.

---

## 5. Merchant app — Flutter ✅

18 screens and widgets, adaptive between bottom bar (phone) and navigation rail
(tablet/desktop).

| Feature | Status | Note |
|---|---|---|
| Login, token session, restore | ✅ | |
| Venue picker for multi-venue accounts | ✅ | Single-venue users never see it |
| Reservations desk: today / next 7 days | ✅ | Grouped by day |
| Confirm / cancel a booking | ✅ | Refuses to confirm an unpaid mobile-money booking, and says why |
| Kitchen queue, grouped by stage | ✅ | Placed → preparing → ready → collected |
| Advance / cancel an order | ✅ | |
| Payments dashboard | ✅ | Collected, awaiting, failed, by method, who to chase |
| Reservation detail with copyable references | ✅ | Built for reconciliation arguments |
| Menu CRUD, mark sold out, item pictures | ✅ | Staff may mark sold out; only owners/managers edit |
| Photos: upload from camera or gallery | ✅ | |
| Opening hours, incl. past midnight | ✅ | Saved as a week, not seven separate writes |
| Venue details (name, tagline, address) | ✅ | |
| Branding: five curated presets + live preview | ✅ | Contrast-checked, no free-form colour picker |
| Staff: add, re-role, remove | ✅ | Owner only; server refuses to leave a venue ownerless |
| Role gating throughout | ✅ | Entries a role cannot use are absent, not shown-and-refused |
| English / French toggle | ✅ | On Manage — reachable without reading a sentence |

**Not present:** creating a venue, creating or editing tables/rooms, moderating
reviews, taking a walk-in order, any analytics beyond payments, printing or
exporting anything, shift/staff scheduling.

---

## 6. Shared package `shared_client` ✅

One internal Dart package both apps depend on, so request shapes and JSON
parsing live in one place: API client, models, the Ember theme baseline,
per-establishment theme scope, adaptive scaffold, layout helpers, geo, and the
locale controller.

96 tests. Moving `LocaleController` here was deliberate — both apps need it and
two copies would drift.

---

## 7. Infrastructure and tooling ✅

- **CI:** six GitHub Actions jobs on every push — ruff, Django tests on SQLite,
  Django tests on PostgreSQL (with `makemigrations --check` so a model change
  without a migration fails), and analyze + test for each of the three Flutter
  packages. `flutter analyze --fatal-infos`, so an info-level lint fails the
  build.
- **Seed data:** `manage.py seed_demo` creates 11 restaurants and 11 lounges
  across Conakry and Labé with varied menus, spaces, hours, bookings, orders,
  reviews, photos and staff. Fixed seed, idempotent. All merchant passwords are
  `sylibooking`.
- **Branching:** every change goes on a feature branch, merges to `dev` after
  CI is green. `main` has not been touched since the first commits and is many
  slices behind.

---

## 8. Not functional — stubbed on purpose

These are deliberate, per the brief ("build against a mock provider first"),
but they are the difference between a demo and a product.

### 8.1 Payments 🟡

`PAYMENT_PROVIDERS` maps both `orange_money` and `mtn_money` to
`MockPaymentProvider`, which **always succeeds** and invents a reference
prefixed `MOCK-`. The whole payment flow — start, poll, confirm, refuse to
confirm an unpaid booking — is real and tested. Only the provider is fake.

Swapping in a real adapter is a settings change, not a code change. What is
missing beyond the adapter itself: webhook/callback handling, retries,
reconciliation against the provider's ledger, and refunds.

### 8.2 SMS 🟡

`ConsoleSmsNotifier` prints the message. `EmailNotifier` uses Django's console
backend in development. Password reset codes are genuinely generated, hashed,
expiring (15 minutes) and attempt-limited (5) — they just never leave the
machine.

### 8.3 Asynchronous work ❌

**There is no Celery, no Redis, and no scheduled work of any kind.** The brief
asked for these to be stubbed; they were skipped entirely rather than stubbed.
Consequences:

- No booking reminders to customers.
- No notification to a merchant when a booking or order arrives — the merchant
  app only learns by pulling to refresh.
- Payment status is refreshed **on demand** when a customer opens the screen,
  not by a poller. A payment that completes while nobody is looking is noticed
  late.

---

## 9. Missing or incomplete

Ordered by how much they matter.

### 9.1 Tables and rooms cannot be managed 🔶 — *blocking*

There is **no `Space` create/update/delete endpoint**. `SpaceSerializer` is
read-only, exposed inside the establishment detail payload. A merchant cannot
add a table, rename one, change its capacity or mark it out of service. The
only route is Django admin.

This is MVP step 1. Until it exists, onboarding a real venue means someone with
admin access typing rows by hand.

### 9.2 A merchant cannot register their own venue 🔶

`POST /api/merchant/establishments/` exists and works — the creator becomes its
owner — and `createEstablishment` exists in the Dart client. **No screen calls
it.** `NoVenueScreen` tells the user "an admin can set one up", which is
currently the literal truth.

### 9.3 Reservations never complete ❌

`Reservation.Status.COMPLETED` is a valid status, the availability engine
respects it, and the merchant UI has a label for it — but **nothing ever sets
it**. There is no "mark as arrived", no automatic transition after the sitting.
So:

- Bookings stay `confirmed` forever.
- "Past bookings" in the customer app are past only by date.
- The payments dashboard's completed-reservations count is always zero.
- A slot is held indefinitely by the availability engine.

### 9.4 Deposits are taken but never consumed ❌

`RESERVATION_DEPOSIT_AMOUNT` (50,000 GNF) is charged for a mobile money
booking. Nothing forfeits it on a no-show, nothing refunds it on arrival,
nothing offsets it against the bill. The word "no-show" appears once, in a
comment. This is the whole commercial point of taking a deposit, and it is not
implemented.

### 9.5 Reviews cannot be moderated 🔶

`Review.is_hidden` exists and the API filters on it, but **no endpoint sets
it** and the merchant app has no reviews screen at all. A merchant cannot see
their reviews in the app, let alone flag one. Moderation is Django admin only.

### 9.6 Smaller gaps

- **No walk-in orders.** `Order` supports standing alone, but only customers
  can create one. A merchant cannot ring one up at the counter.
- **No kitchen tickets** in the printed sense — the queue is on screen only.
- **No merchant notification** of new bookings or orders (see 8.3).
- **No analytics** beyond the payments dashboard: no covers per night, no
  turnover rate, no popular dishes, no repeat-customer view.
- **No customer profile editing** — a name and phone are captured per booking,
  not maintained.
- **No account deletion** — relevant if this ever meets a privacy regime.
- **No pagination in the merchant app.** The reservations and orders lists
  fetch and render everything. Fine for a venue with 20 bookings a night;
  visibly not fine at 500.
- **No rate limiting** on login or password reset beyond the per-code attempt
  cap.
- **No observability** — no error reporting, no logging strategy, no metrics.
- **No deployment** — no Dockerfile, no host, no CD. It runs on a laptop.

---

## 10. Known defects and rough edges

Small, real, and visible.

| Where | Problem |
|---|---|
| Merchant desk, range chips | **"7 prochains jour"** — the final "s" is clipped. English clips too ("Next 7 day:"). The segment is a hair too narrow for its label; `softWrap: false` means it clips rather than wraps. |
| Merchant app on tablet | Content sits in a narrow centred column with large empty margins. Deliberate max-width, but at 2560px it reads as unfinished rather than as breathing room. |
| Customer browse, filter chips | Still a sideways-scrolling strip. The venue photos and day picker were reworked to avoid horizontal scrolling; the chips were not. |
| Seed data | Bookings cluster around the fixed seed date, so "today" is usually empty on a fresh run. Misleading when demoing. |
| `main` | Many slices behind `dev` and never merged. |

---

## 11. What to improve, in order

**1. Build `Space` management** — endpoint plus a merchant screen. This is the
last piece of MVP step 1 and it blocks onboarding any real venue.

**2. Add the venue-creation screen** — the API is already there and tested;
this is a screen and a form, perhaps half a day.

**3. Close the reservation lifecycle** — a "mark as arrived / completed" action
for merchants, and a rule for what happens to a booking whose time has passed.
Without it the data model tells a lie that grows over time.

**4. Decide what a deposit means** — forfeit on no-show, offset against the
bill, or refund. Any of the three is fine; none of them is not.

**5. Introduce the async layer** — Celery + Redis, even stubbed to log. Booking
reminders and merchant notifications both need it, and retrofitting it later
touches every write path.

**6. Wire one real payment provider sandbox** — Orange Money first. The
interface is ready; the work is the adapter, the callback endpoint, and
reconciliation.

**7. Give merchants their reviews** — read at minimum, flag-for-moderation
ideally. A merchant who cannot see their own reviews will find them on
Facebook instead.

**8. Paginate the merchant lists** before a venue with real volume meets them.

**9. Fix the clipped chip and the tablet whitespace** — small, visible, cheap.

**10. Plan deployment** — nothing is deployable today. Docker, a host, a
managed Postgres, static/media storage, and CD.

---

## 12. Honest summary

The **spine of the product is genuinely built and genuinely tested**: a
customer can find a venue, see real availability, book, order food ahead, pay,
track it and review it; a merchant can work the floor, run the kitchen queue,
manage their menu, staff, hours, photos and branding, and see their money —
all in English or French, on a phone or a tablet.

911 tests and a six-job CI pipeline mean the parts that exist are unlikely to
break silently. The reservation logic — double-booking, past-midnight hours,
role gating — is the best-covered code in the repository, which is the right
place to have spent the effort.

What it is **not** yet is operable without a developer. A real merchant in
Conakry cannot sign up, cannot enter their tables, and cannot take a real
payment. Those three things — §9.1, §9.2, §8.1 — are the distance between this
and a pilot.
