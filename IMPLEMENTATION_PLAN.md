# Sylibooking — Implementation Plan

**Written 2 August 2026**, from the audit in [`PROJECT_STATUS.md`](PROJECT_STATUS.md).
Covers everything that document marks 🟡 stubbed, 🔶 backend-only, ❌ missing,
or listed as a defect — plus the improvement suggestions, sequenced.

**Continued 12 August 2026** from [`PLATFORM_ASSESSMENT.md`](PLATFORM_ASSESSMENT.md).
Slices 1–22 are built and merged; slices 23–45 are the new plan and begin at
["Continuation"](#continuation--written-12-august-2026). Read that section for
current work — everything before it is a record of what was done.

---

## How to use this

Each slice below is a **feature branch that merges into `dev` once CI is
green**, matching how the project has been built so far. A slice is sized to
be finished and merged, not left half-done overnight.

Every slice states:

- **Goal** — what is true when it is done
- **Why here** — why it sits at this point in the order
- **Backend / Client** — the files it touches
- **Tests** — what must be written alongside, not after
- **Done when** — the check that closes it
- **Size** — S (a sitting), M (a day-ish), L (multi-day), at the pace of the
  slices already delivered

Sizes assume the existing conventions hold: tests alongside each piece, widget
tests at 360×900, `flutter analyze --fatal-infos`, ruff clean, six CI jobs
green before merge.

---

## Decisions needed from you

Four slices are blocked on a product decision, not on engineering. They are
called out again in place, but they are collected here because answering them
early keeps the plan moving.

| # | Decision | Blocks | My recommendation |
|---|---|---|---|
| D1 | **What a deposit means.** Forfeit on no-show, offset against the bill, or refund on arrival? | Slice 5 | **Offset against the bill, forfeit on no-show.** It is the only version a customer perceives as fair and a merchant perceives as worth having. |
| D2 | **How long after its time a booking is a no-show** — as a default per establishment type, not one number for both. | Slice 4, 5 | **30 minutes for a restaurant, 90 for a lounge.** A lounge table is not lost at minute 16, and its turnover pressure comes late. A restaurant table held 90 minutes through a dinner rush costs more in refused walk-ins than the 50,000 GNF deposit is worth — the grace period would be losing the venue money to protect a smaller sum. Per-venue override stays a later door, as planned. |
| D3 | **May staff edit tables/rooms, or owners and managers only?** | Slice 1, 2 | **Owners and managers**, matching hours and menu editing. Staff already mark items sold out; spaces are structural. |
| D4 | **Which SMS aggregator.** | Slice 9 | Needs a local quote — this is a commercial choice, not a technical one. The `Notifier` interface is already in place, so the code cost is one adapter whichever you pick. |

Two more will come up later and can wait: whether merchants may hide reviews or
only flag them (Slice 14), and where this is hosted (Slice 21).

**Both were since decided by building them.** Reviews are flag-only — a
merchant sets `flagged_at` and a reason, and only an admin can hide one.
Hosting is containers plus `deploy/render.yaml`, with media on Cloudflare R2.

---

## Sequencing at a glance

```
DONE — merged to dev
Phase 0  Unblock the MVP          Slices 1–3    ← nothing real can happen without this
Phase 1  Close the lifecycle      Slices 4–5    ← stops the data telling a lie
Phase 2  The async layer          Slices 6–8    ← retrofitting later touches every write path
Phase 3  Real money               Slice 10 only ← 9, 11, 12, 13 never built: blocked on credentials
Phase 4  Merchant completeness    Slices 14–16
Phase 5  Correctness and polish   Slices 17–19
Phase 6  Operability              Slices 20–22

NEXT — planned 12 August, from PLATFORM_ASSESSMENT.md
Phase 7  Stop the bleeding        Slices 23–28  ← one week; 23 repairs CI, which the rest is measured with
Phase 8  Real money, real push    Slices 29–33  ← every slice blocked on credentials, not engineering
Phase 9  What a merchant asks for Slices 34–36
Phase 10 Fit for this market      Slices 37–39
Phase 11 Growth                   Slices 40–45
```

Phases 7 and 8 are **parallel, not sequential**: Phase 8 waits on paperwork you
have to chase, and Phase 7 is a week of engineering that needs nobody's
permission. Start both.

The order is not arbitrary. Phase 0 is the difference between "demo" and
"a merchant can use this". Phase 1 fixes a model that grows more wrong every
day it runs. Phase 2 is early **because adding an async layer late means
revisiting every write path** — cheaper now, at 12k lines, than at 30k.

---

# Phase 0 — Unblock the MVP

*Nothing in this phase is new product. It is the part of MVP step 1 that was
never built, and it blocks onboarding a single real venue.*

## Slice 1 — `Space` CRUD API 🔶 → ✅

**Goal.** A merchant can create, rename, re-capacity, retype and remove a
table, VIP room or terrace over the API, with the same membership checks every
other merchant route carries.

**Why here.** `PROJECT_STATUS.md` §9.1. There is no write endpoint for `Space`
at all; `SpaceSerializer` is read-only inside the establishment payload. This
is MVP step 1 and everything else in Phase 0 depends on it.

**Backend.**
- `backend/api/serializers.py` — add `SpaceWriteSerializer` (name, type,
  capacity). Validate capacity ≥ 1. Surface the existing
  `unique_space_name_per_establishment` constraint as a field error rather
  than a 500.
- `backend/api/merchant.py` — `MerchantSpacesView` (GET list, POST create) and
  `MerchantSpaceItemView` (PATCH, DELETE), modelled directly on
  `MerchantMenuView` / `MerchantMenuItemView`. Use
  `require_operations_access` to read and `require_profile_access` to write
  (**pending D3**).
- `backend/api/urls.py` — `merchant/establishments/<pk>/spaces/` and
  `.../spaces/<space_id>/`.
- **Deletion needs a rule.** A `Space` with bookings against it cannot simply
  vanish — `Reservation.space` is a FK. Add `Space.is_active` and make DELETE
  a deactivation: the space stops appearing in availability, existing bookings
  survive, and history stays readable. A space with no bookings at all may be
  hard-deleted.
- `backend/reservations/availability.py` — exclude inactive spaces.

**Tests.** ~20, in a new `backend/api/test_spaces.py`:
- Owner and manager can create; staff cannot (per D3); a non-member gets 404,
  not 403 (matching the existing posture of not confirming a venue exists).
- Duplicate name in one venue is a field error; the same name in *another*
  venue is fine.
- Capacity 0 and negative are refused.
- Deactivating a space removes it from availability but leaves its bookings
  intact and readable.
- Hard delete is refused when bookings exist.
- A space belonging to another venue cannot be edited through your venue's URL.

**Done when.** A venue's whole seating plan can be built over the API by an
owner, and `seed_demo` is no longer the only way spaces come into existence.

**Size:** M

---

## Slice 2 — Tables and rooms in the merchant app 🔶 → ✅

**Goal.** "Tables and rooms" appears on Manage; an owner can lay out their
venue from a phone.

**Why here.** Slice 1 without this is still admin-only in practice.

**Client.**
- `apps/shared_client/lib/src/api_client.dart` — `merchantSpaces`,
  `createSpace`, `updateSpace`, `deactivateSpace`.
- `apps/shared_client/lib/src/models.dart` — extend `Space` with `isActive`.
- `apps/merchant_app/lib/src/screens/spaces_screen.dart` — list grouped by
  type, each row showing name and capacity; a bottom-sheet form to add or edit
  (same pattern as `_MenuItemForm`); deactivate behind a confirmation that
  says what happens to existing bookings.
- `apps/merchant_app/lib/src/screens/manage_screen.dart` — a `_Entry` for it,
  gated on `role.canEditProfile`, placed above Opening hours (a venue is
  defined by its rooms before its hours).
- `apps/merchant_app/lib/l10n/*.arb` — ~14 keys, both languages.

**Tests.** ~12 widget tests: the entry is absent for staff; adding a space
posts the right body; a duplicate name surfaces the server's message; the
deactivate dialog explains the consequence; the form fits 360×900; French
labels do not overflow.

**Done when.** A venue with zero spaces can be laid out entirely in the app,
and a customer can then book one of them.

**Size:** M

---

## Slice 3 — Venue self-registration 🔶 → ✅

**Goal.** `NoVenueScreen` offers "Create your venue" instead of telling the
user to find an admin.

**Why here.** §9.2 — `POST /api/merchant/establishments/` already works and is
tested, and `createEstablishment` already exists in the Dart client. **No
screen calls either.** This is the cheapest real unblock in the plan.

**Client.**
- `apps/merchant_app/lib/src/screens/create_venue_screen.dart` — name, type
  (lounge / restaurant), city, address. Nothing else: tagline, description,
  hours, branding and spaces all have their own screens already, and asking
  for them here would be a wall of fields between a merchant and their first
  venue.
- On success: select the new venue, then route straight into Slice 2's spaces
  screen with a line explaining that a venue needs somewhere to sit before it
  can take a booking.
- `venue_picker_screen.dart` — a "New venue" action for accounts that already
  have one.
- `manage_screen.dart` — nothing; creating is not managing.

**Backend.** None, unless D3 changes who may create.

**Tests.** ~8: the empty-state button appears only when the account has no
venue; a created venue makes the caller its owner; validation errors land on
the right fields; the post-create route lands on spaces.

**Done when.** A brand-new merchant account can go from nothing to a bookable
venue without anyone touching Django admin.

**Size:** S

> **After Phase 0, the MVP in `CLAUDE.md` is genuinely complete.** Everything
> below improves a working product rather than finishing an unfinished one.

---

# Phase 1 — Close the lifecycle

## Slice 4 — Reservations complete ❌ → ✅

**Goal.** A booking reaches an end state. Slots stop being held forever.

**Why here.** §9.3. `COMPLETED` is a valid status that **nothing ever sets**.
Bookings stay `confirmed` indefinitely, availability holds the slot, "past
bookings" are past only by date, and the dashboard's completed count is
permanently zero. This gets worse with every booking taken.

**Backend.**
- `backend/api/views.py` — a `complete` action beside `confirm` and `cancel`,
  operations access, refusing a booking that is cancelled or in the future.
- `backend/reservations/models.py` — `arrived_at`, set when a merchant marks
  arrival.
- **The no-show window is per establishment type** (**D2**), not one constant:

  ```python
  # A lounge table is not lost at minute 16; a restaurant table held through
  # a dinner service is. One number cannot serve both.
  NO_SHOW_WINDOW_MINUTES = {
      'restaurant': config('NO_SHOW_WINDOW_RESTAURANT', default=30, cast=int),
      'lounge': config('NO_SHOW_WINDOW_LOUNGE', default=90, cast=int),
  }
  ```

  with a single resolver — `no_show_window(establishment)` in
  `backend/reservations/` — that reads the type default today and will consult
  a per-venue override column later. One function, so the later door opens in
  one place rather than at every call site.
- **The window is captured on the booking, not read at lapse time.**
  `Reservation.no_show_after_minutes`, set at creation from the resolver. A
  customer is told the grace period when they book; if a merchant later
  shortens it, that must not retroactively turn an existing booking into a
  forfeited deposit. This matters more in Slice 5 than here, but the field has
  to exist from the start or the history cannot support the argument.
- **Automatic lapse.** A confirmed booking whose time passed by more than
  *its own* window and was never marked arrived becomes `no_show` — a new
  status, distinct from `completed`, because the two mean opposite things
  commercially and Slice 5 needs to tell them apart. Implemented as a
  management command now, moved onto the scheduler in Slice 7.
- `backend/reservations/availability.py` — `no_show` releases the slot;
  `completed` continues to hold it.

**Client.**
- Merchant: a "Mark arrived" action on the reservation card and detail screen,
  visible only for a confirmed booking whose time has come.
- Customer: the booking screen states the grace period in words — "we will
  hold your table for 30 minutes" — which now varies by venue, so it is a
  placeholder string rather than a fixed one. A forfeited deposit is only
  defensible if this sentence was on screen beforehand.
- Customer: past bookings read "Completed" or "Missed" rather than sitting on
  "Confirmed" forever.
- Both catalogues.

**Tests.** ~30 backend: the action's role gating; refusing to complete a
future or cancelled booking; **the lapse boundary at exactly the window, run
once per type** — a restaurant booking 31 minutes late lapses while a lounge
booking at the same delay does not; a no-show releasing its slot; a completed
booking still holding it; idempotency when the command runs twice; and the one
that protects the customer — **changing a venue's window does not move the
deadline of a booking already taken**. Plus widget tests both sides, including
that the stated grace period matches the venue's type.

**Done when.** A day's bookings can be worked to a conclusion, yesterday's
data is a true record, and a restaurant is not holding tables to a lounge's
timetable.

**Size:** M

---

## Slice 5 — Deposits mean something ❌ → ✅

**Goal.** The 50,000 GNF taken from a mobile money booking has a defined fate.

**Why here.** §9.4. The deposit is charged and then nothing happens to it. It
is the commercial point of taking one, and it depends on Slice 4 being able to
tell a no-show from a completed visit.

**Blocked on D1 and D2.** Written below for my recommendation — offset on
arrival, forfeit on no-show, against the per-type window from Slice 4.

**Backend.**
- `backend/payments/models.py` — `Payment.outcome`: `offset`, `forfeited`,
  `refunded`, `none`. The deposit stays `completed` as a *payment*; its
  outcome is a separate axis.
- `backend/payments/services.py` — `settle_deposit(reservation)`, called when a
  booking completes (offset) or lapses to no-show (forfeit).
- **Forfeiture reads the booking's own `no_show_after_minutes`**, captured at
  creation in Slice 4 — never the current setting. A merchant who shortens
  their window on Tuesday must not thereby forfeit a deposit taken on Monday
  under a longer one. This is the whole reason that field exists, and it is
  the first thing a customer will dispute.
- A refund path on the provider interface — `PaymentProvider.refund()` — even
  though the mock is the only implementation until Slice 11. Designing it now
  keeps Slice 11 from being an interface change as well as an adapter.
- Dashboard: forfeited deposits are revenue and belong in the totals; offset
  ones are not, and double-counting them would overstate takings.

**Client.**
- Customer: the booking screen says plainly what happens to the deposit before
  it is taken — including the grace period, which now differs between a
  restaurant and a lounge — and the confirmation repeats it. This is the
  sentence that decides whether deposits get accepted in the market at all,
  and it is what makes a forfeiture defensible rather than a surprise. Worth
  writing carefully in both languages.
- Merchant: the reservation detail shows the deposit's outcome, and the
  payments dashboard separates forfeited from collected.

**Tests.** ~24: each transition; a cash booking having no deposit to settle;
settling twice being a no-op; the dashboard's arithmetic under a mix;
forfeiture at a restaurant's 30 minutes and a lounge's 90 from the same
fixture; and **a booking whose venue changed its window after the booking was
taken settling against the window it was sold under**.

**Done when.** Every deposit taken has an outcome, the dashboard's total is
defensible to a merchant counting cash, and every forfeiture can be explained
to the customer it was taken from.

**Size:** M

---

# Phase 2 — The async layer

*Early on purpose. §8.3: there is no Celery, no Redis, no scheduled work of
any kind — the brief asked for these to be stubbed and they were skipped.
Retrofitting an async layer touches every write path, so it is cheaper at 12k
lines than at 30k.*

## Slice 6 — Celery and Redis, doing almost nothing ❌ → 🟡

**Goal.** A task queue exists, runs in CI, and has exactly one trivial task on
it. No behaviour changes.

**Why here.** A slice that adds infrastructure *and* features at once is a
slice where a failure is ambiguous. This one is deliberately boring.

**Backend.**
- `backend/config/celery.py`, `requirements.txt` (celery, redis), settings for
  the broker with an eager mode for tests.
- `backend/notifications/` — a new app owning task definitions, so tasks do
  not accrete inside `api/`.
- One task: `send_test_notification`, which logs. Proves wiring end to end.
- `docker-compose.yml` for a local Redis — the first piece of Slice 21.
- CI: a Redis service on the Postgres job; tasks eager elsewhere.

**Tests.** ~8: a task runs eagerly under test; a failing task retries and then
gives up rather than hanging; the queue being unreachable does not 500 a
request that enqueued work.

**Done when.** `celery -A config worker` runs locally and CI is still green.

**Size:** M

---

## Slice 7 — Reminders and merchant alerts 🟡 → ✅

**Goal.** A customer is reminded before their booking. A merchant learns of a
new booking or order without pulling to refresh.

**Why here.** §8.3 and §9.6 — the merchant app currently only finds out by
being refreshed by hand, which is not how a service works.

**Backend.**
- Tasks: booking reminder (a few hours ahead, per venue), order-ready
  notification, and the no-show lapse sweep from Slice 4 moved onto a beat
  schedule.
- Reminders go through the existing `Notifier` interface — console SMS until
  Slice 9, which means this slice is *fully testable* without an SMS contract.
- `notifications/models.py` — a log row per notification: what, to whom, which
  channel, delivered or not. Without this, "did the customer get the reminder"
  has no answer, and it is the first question a merchant will ask.
- Idempotency: one reminder per booking, enforced in the database, not by
  hoping the scheduler does not double-fire.

**Client.** Merchant: a quiet unread marker on the desk when new work has
arrived since the screen was last loaded. Not a push notification yet — that
needs Firebase and a signing story, which is Slice 22.

**Tests.** ~20: reminder timing against venue hours; no reminder for a
cancelled booking; exactly one reminder when the beat runs twice; a notifier
raising does not lose the booking.

**Done when.** A booking made today produces a logged reminder tomorrow
without anyone running anything by hand.

**Size:** L

---

## Slice 8 — Payments stop needing a watcher 🟡 → ✅

**Goal.** A payment that completes while nobody is looking is noticed.

**Why here.** §8.3 — `refresh_payment` is only called when a customer opens
the payment screen. With a real provider this becomes a correctness problem
rather than a latency one.

**Backend.** A task polling pending payments on a decaying schedule, giving up
after a defined window and marking them failed. Runs against the mock exactly
as it will against a real provider, so Slice 11 inherits a working poller.

**Tests.** ~12: a payment completing between polls; giving up cleanly; not
polling something already settled; the poller confirming the reservation the
same way the on-demand path does.

**Done when.** The customer payment screen has nothing to do but read state.

**Size:** M

---

# Phase 3 — Real money

## Slice 9 — SMS that leaves the machine 🟡 → ✅

**Goal.** A password reset code and a booking reminder reach an actual phone.

**Why here.** It gates the usefulness of Slice 7, and it is smaller than the
payment work — a good first real integration.

**Blocked on D4** (which aggregator).

**Backend.** One `Notifier` implementation, a credential in settings, delivery
receipts written to Slice 7's log, and a sane failure mode: a reset code that
cannot be sent must say so rather than claim success. The interface, the
masking helper and the tests already exist.

**Tests.** ~10, against a stubbed HTTP client — never the live gateway.

**Size:** S–M, depending on the aggregator's API.

---

## Slice 10 — Throttle the doors real money opens ❌ → ✅

**Goal.** Login, registration, password reset and — above all — booking and
order creation cannot be hammered, **before** a live payment gateway is
attached to them.

**Why here.** This was Slice 18, in "Correctness and polish". It is not
polish. Booking creation is unauthenticated by design, which is correct, and
today the worst an abuser gets is junk rows in a table. The moment Slice 11
lands, the same unauthenticated endpoint initiates a **real payment against a
real provider account**, and three things change character at once:

- **Payment prompts are sent to a phone number the caller chose.** Mobile
  money initiation pushes a USSD or app prompt to the payer. An unthrottled
  booking-create → payment-initiate chain lets anyone fire prompts at any
  number in Guinea, as often as they like, from our provider account. That is
  a harassment vector wearing our name, and it is the single strongest reason
  this moves.
- **Provider quota and per-call cost** become someone else's lever to pull.
- **Reconciliation noise** (Slice 13) is only readable if the ledger is not
  full of abandoned initiations.

Ordering it *after* the integration would mean shipping that window open and
closing it later. Ordering it before costs nothing — the throttles are
testable against the mock exactly as they will behave against the real thing.

**Backend.**
- DRF throttle classes, scoped per endpoint rather than one global rate:
  - `POST /api/auth/login/` — tight, per IP and per username, so a merchant
    account cannot be walked through a password list.
  - `POST /api/customer/register/`
  - `POST /api/customer/password-reset/` — **the gap worth naming.** The
    5-attempt cap is *per code*; nothing caps how many codes may be
    requested. Unthrottled, that is unlimited attempts wearing a fresh code
    each time, and once Slice 9 lands it is also unlimited SMS billed to us.
  - `POST /api/customer/password-reset/confirm/`
  - `POST /api/reservations/` and `POST /api/orders/` — the unauthenticated
    pair. Per IP *and* per phone number.
- A per-phone cap on bookings and orders in a rolling window, which is the
  one that actually blunts prompt-spam, since an abuser rotating IPs still
  has to pick a victim number.
- Failures must be a clean `429` with `Retry-After`, not a 500.

**Client.** Both apps render a 429 as a plain "too many attempts, try again in
a moment" rather than the generic failure message — in both languages. A
throttle the user cannot distinguish from a crash gets reported as a crash.

**Tests.** ~18: each endpoint's limit and its reset; per-username login
throttling not locking out an innocent third party who shares an IP; the
password-reset *request* cap, tested explicitly since it is the hole this
slice exists to close; a 429 surfacing as a message in both apps; throttles
off under test elsewhere so the other 900 tests are unaffected.

**Done when.** Every unauthenticated write path has a ceiling, and the
payment work lands behind it rather than in front of it.

**Size:** S–M

---

## Slice 11 — Orange Money, sandbox 🟡 → ✅

**Goal.** A real payment, in a sandbox, end to end.

**Why here.** §8.1. The interface, the flow, the refusal-to-confirm-unpaid
rule, the dashboard and now the poller are all built and tested against the
mock. This slice is genuinely just the adapter — which is exactly what the
brief intended by "build against a mock provider first".

**Backend.**
- `payments/providers.py` — `OrangeMoneyProvider` implementing
  `initiate_payment`, `check_status` and the `refund` added in Slice 5.
- **A callback endpoint.** Providers push results; relying only on polling
  wastes the notification and delays the customer. Needs signature
  verification and replay protection — a callback endpoint that trusts its
  input is a way to mark any booking paid.
- Settings map `orange_money` to the real class; the mock stays for tests and
  demos.
- Timeouts, retries, and a clear distinction between "payment failed" and "we
  do not know" — `PaymentError` already encodes this.

**Tests.** ~25 against a stubbed HTTP layer: initiate, status, callback
signature valid and invalid, replayed callback, provider timeout, a callback
arriving before the poller, a callback for an unknown reference.

**Done when.** A sandbox payment moves a real booking to paid, both by
callback and by poller, and neither path double-confirms.

**Size:** L

---

## Slice 12 — MTN Mobile Money ✅

Same shape as Slice 11 against a second API. Cheaper — the callback pattern,
the retry policy and the tests are established. **Size:** M

---

## Slice 13 — Reconciliation and refunds 🟡 → ✅

**Goal.** A merchant can answer "did this land" without calling the provider.

**Why here.** §8.1 names reconciliation as missing. The reservation detail
screen was built for exactly this argument — it already shows a copyable
provider reference — but there is nothing to reconcile *against*.

**Backend.** A daily job pulling the provider's settled transactions and
flagging anything the two ledgers disagree about. Refunds through the
interface added in Slice 5.

**Client.** Merchant: a "Doesn't match" section on the payments dashboard,
beside "Needs chasing".

**Tests.** ~15, including the case that matters: provider says paid, we say
pending.

**Size:** M

---

# Phase 4 — Merchant completeness

## Slice 14 — Merchants can see their reviews 🔶 → ✅

**Goal.** A merchant reads their reviews in the app and can flag one.

**Why here.** §9.5. `Review.is_hidden` exists and the API filters on it, but
**no endpoint sets it** and the merchant app has no reviews screen at all. A
merchant who cannot see their own reviews will find them on Facebook instead.

**Decision needed:** may a merchant hide a review outright, or only flag it
for an admin? I recommend **flag only** — a venue that can delete its own bad
reviews has a ratings system worth nothing, and the trust cost lands on the
platform.

**Backend.** A merchant reviews list (including hidden, with a marker), and a
`flag` action writing a reason. Admin retains `is_hidden`.

**Client.** A Manage entry: rating distribution, recent reviews, flag with a
reason. Restaurants and lounges live or die on this and it is currently
invisible to them.

**Tests.** ~18: role gating, flagging once, a flagged review still visible to
customers until an admin acts, the average rating ignoring hidden reviews.

**Size:** M

---

## Slice 15 — Walk-in orders ❌ → ✅

**Goal.** A merchant rings up an order at the counter.

**Why here.** §9.6. `Order.reservation` is already nullable precisely so an
order can stand alone — the model anticipated this and the UI never arrived.

**Backend.** Merchant order creation, membership-checked, cash by default.
Rules on who may create (staff yes — it is floor work).

**Client.** An "Add order" action on the kitchen queue, reusing the customer
app's menu-picker patterns.

**Tests.** ~15, including that a walk-in with no customer account and no phone
is valid, and that it appears in the same queue as a customer's.

**Size:** M

---

## Slice 16 — Pagination in the merchant app ❌ → ✅

**Goal.** The desk and the queue stay usable at real volume.

**Why here.** §9.6. Both lists fetch and render everything. Fine at 20
bookings a night; visibly not fine at 500, and the first venue that hits it
will be the one worth keeping.

**Backend.** Page the merchant reservations and orders endpoints, defaulting
to a sane window (today, then paged).

**Client.** Incremental loading on both lists, and a test that fabricates 500
bookings and asserts the frame budget — this is a slice where the test is the
point.

**Size:** M

---

# Phase 5 — Correctness and polish

## Slice 17 — The visible defects ✅

From §10. Small, cheap, and they are what a merchant notices first.

- **"7 prochains jour"** — the clipped chip. Let the segment size to its
  content or drop to `FittedBox`; assert the rendered width against the label
  in a test so it cannot silently return.
- **Tablet whitespace** — the merchant content column is a narrow strip in a
  2560px window. Either widen the max width or use the space for a second
  column (the day's list beside the selected booking).
- **Browse filter chips** — still a sideways-scrolling strip, the pattern
  explicitly rejected for photos and the day picker. Make them wrap.
- **Seed data** — anchor some bookings to "today at run time" so a fresh
  `seed_demo` demos well.

**Size:** S

---

## Slice 18 — Customer profile and account deletion ❌ → ✅

**Goal.** A returning customer's details are theirs, not re-typed per booking;
an account can be deleted.

**Why here.** §9.6. Name and phone are captured per booking and never
maintained. Deletion matters the moment this meets a privacy regime, and
retrofitting deletion across bookings, orders, reviews, favourites and reset
codes is far worse later than now.

**Backend.** Profile update; deletion that anonymises rather than cascades —
a deleted account must not erase a merchant's revenue history. Decide and
document what survives.

**Tests.** ~15, including that a deleted customer's past bookings still count
in the merchant's dashboard while carrying no personal data.

**Size:** M

---

## Slice 19 — The rest of the abuse surface ❌ → ✅

**Goal.** The systematic sweep, once the exposed paths are already closed.

**Why here.** The urgent half of this slice moved to Slice 10, ahead of the
payment integration. What is left is genuinely a polish pass: it protects
against nuisance and cost, not against a live gateway being used as a weapon,
and some of it wants the observability from Slice 20 to be worth tuning.

**Scope — what stayed behind, and why.**
- **A global default throttle** across the remaining API surface, so a new
  endpoint is covered by default rather than by remembering. Deliberately not
  in Slice 10: a blanket rate needs real traffic to size, and guessing it
  early risks throttling legitimate use during the first pilot.
- **Read-path scraping** — the browse and search endpoints are public and
  currently unlimited. A competitor pulling the whole venue list nightly is
  an annoyance, not an exposure.
- **Upload abuse** — photo size and count caps per venue per day. Bounded
  today by needing merchant credentials.
- **Enumeration hardening** — the password-reset lookup answers in constant
  time regardless of whether the identifier exists. The *message* is already
  identical either way; the timing is not.
- **Review and favourite spam** — largely blunted already, since a review is
  `OneToOne` with a reservation and a favourite is unique per user and venue.
  Worth confirming with tests rather than assuming.
- **Tuning what Slice 10 set**, using the throttle-hit metrics from Slice 20.
  This is the part that genuinely cannot happen earlier.

**Tests.** ~12, including that the global default does not shadow the tighter
per-endpoint limits set in Slice 10.

**Size:** S

---

# Phase 6 — Operability

## Slice 20 — Observability ❌ → ✅

**Goal.** When something breaks in Conakry, you find out from a dashboard
rather than from a merchant.

**Backend.** Structured logging, an error reporter (Sentry or equivalent), a
health endpoint, and metrics on the numbers that matter: bookings created,
payments initiated versus completed, notification delivery rate. **Slice 7's
notification log and Slice 13's reconciliation are the two places where silent
failure is most expensive**, so instrument those first.

**Client.** Crash reporting in both apps, behind a consent line.

**Size:** M

---

## Slice 21 — Deployment ❌ → ✅

**Goal.** It runs somewhere other than a laptop.

**Why here.** §9.6 — no Dockerfile, no host, no CD. Everything above is
untestable in the real world until this exists; it sits here only because it
needs the async layer and Redis from Slice 6 to be worth doing once.

**Scope.** Dockerfile and compose (extending Slice 6's), a managed Postgres,
media on object storage rather than local disk (`backend/media/` will not
survive a redeploy), static files, TLS, environment/secret handling, a
migration step, and CD from `main`.

**Decision needed:** where. It is worth weighing latency from Guinea and
whether a regional provider is easier to pay than a global one — a technically
better host you cannot pay for is not a better host.

**Size:** L

---

## Slice 22 — Release process and push ❌ → ✅

- `main` is many slices behind `dev` and has never been merged. Define what
  `main` means — I suggest "what is deployed" — and merge to it deliberately,
  with a tag.
- Store builds, signing keys, and a Play Store listing.
- Push notifications (Firebase), which turns Slice 7's alerts into something a
  merchant sees without opening the app.

**Size:** L

---

# Continuation — written 12 August 2026

**Slices 1–22 above are built and merged to `dev`.** Everything from here is
new, and comes from the audit in
[`PLATFORM_ASSESSMENT.md`](PLATFORM_ASSESSMENT.md) rather than from
`PROJECT_STATUS.md`, which that audit supersedes.

This section **replaces the earlier Phase 7 sketch** (a six-row table that
claimed slices 23–28). The topics survive; the sequence does not. The audit
found four defects and one red test that outrank every growth feature, so those
come first and the growth work moves back.

**On Phase 3.** Slices 9, 11, 12 and 13 above were written but never built —
they need payment sandbox credentials and an SMS aggregator, which are outside
the repository. Only Slice 10 (throttles) shipped. Those four are re-planned
here as **Slices 29–32** against what the code actually looks like today, which
has moved since August 2. Where the old slice and the new one disagree, the new
one is current; the old text is left in place as the record of what was
intended.

## Decisions needed from you — second round

| # | Decision | Blocks | My recommendation |
|---|---|---|---|
| D4 | **Which SMS aggregator.** Still open from the first round. | 32 | Unchanged: a commercial choice needing a local quote. The `Notifier` interface means one adapter whichever you pick. |
| D5 | **Which third language.** Susu, Pular or Malinké first? | 37 | **Susu**, as Conakry's lingua franca — the pilot city decides this, not national numbers. Pular follows with Labé. |
| D6 | **What "no-show rate" counts.** Lapsed bookings only, or lapsed + late cancellations? | 34 | **Both, shown separately.** A merchant reads them differently: one is a stranger who never came, the other is a customer who warned them. |
| ~~D7~~ | ~~**May a merchant hide a review, or only flag it?**~~ **Resolved — already shipped as flag-only.** | — | Listing it as open was this document's error, not an open question. `MerchantReviewFlagView` sets `flagged_at` and `flagged_reason`; `is_hidden` is readable but not writable by any merchant route, so only an admin can hide one. That is the recommendation, built in Slice 14. |
| D8 | **Does loyalty reward money or status?** A discount, or priority booking? | 40 | **Priority booking and a held table**, not a discount. Margin in this market is thin, and a guaranteed table on a Friday is worth more to a regular than 5% off. |

---

# Phase 7 — Stop the bleeding

*Four defects and two pieces of housekeeping. None is large; all of them make
everything after them cheaper or more trustworthy. This phase should be one
week's work and should not be reordered — Slice 23 in particular blocks the
signal every later slice depends on.*

## Slice 23 — A test suite that does not depend on the hour ❌ → ✅

**Goal.** `flutter test` passes at 03:00 and at 20:00, and a red CI job means
something is actually broken.

**Why here.** `PLATFORM_ASSESSMENT.md` §7.1. The merchant suite has one failing
test — *"staff can still work the day"* — and it fails not intermittently but
**for nineteen hours of every day**. The fixture books today at 19:00
(`widget_test.dart:146`), while the button under test only appears once the
sitting has started (`reservation_card.dart:51`). CI runs `ubuntu-latest` in
UTC with no `TZ` set, so the merchant job fails on any push before 19:00 UTC.

Everything else in this plan is verified by CI. Fixing CI first is not
housekeeping — it is the instrument the rest of the work is measured with.

**Client.**
- `apps/merchant_app/test/widget_test.dart` — give `booking()` a `when`
  parameter defaulting to a time already under way
  (`DateTime.now().subtract(const Duration(hours: 1))`). The tests that care
  about a *future* booking pass an explicit future time, so each test states
  the state it needs instead of inheriting a wall-clock accident.
- **Sweep for siblings.** Grep both apps' tests for fixed hours —
  `DateTime(now.year, now.month, now.day, <n>)` — and give each the same
  treatment. The repo has met this bug before (`Stop the queue pagination tests
  failing after 23:30 in Conakry`), which means the pattern recurs and a
  one-test fix will not hold.
- `.github/workflows/ci.yml` — add a deliberately awkward `TZ` to the Flutter
  job (`Pacific/Kiritimati`, UTC+14) so a test that secretly depends on the
  clock fails in CI rather than at 01:00 on someone's laptop.

**Tests.** The suite itself is the test. Prove the fix by running the merchant
suite with `TZ` forced to at least three zones spanning the day.

**Done when.** All four suites pass under any `TZ`, and CI carries a
non-UTC timezone so this class of bug cannot come back unnoticed.

**Size:** S

---

## Slice 24 — The network layer survives a bad network ❌ → ✅

**Goal.** No request can hang forever. A slow network says so, and a read that
failed once is retried before the user is told anything.

**Why here.** §7.2. `grep '\.timeout('` across all three Dart packages returns
nothing, and `package:http` has no default. On a Conakry mobile connection the
common failure is a stall, not a refusal — so today the app shows a spinner
that never resolves and offers no way out. This is the most user-visible
weakness in the product and it is fixed in one file.

**Client.**
- `shared_client/lib/src/api_client.dart` — a `timeout` on every request
  (suggest 15s for reads, 30s for writes; writes are longer because a payment
  initiation legitimately takes longer than a list). Map `TimeoutException` to a
  distinct `ApiException` kind so callers can tell "slow" from "broken".
- **Retry reads, never writes.** Two retries with backoff on GET only. A
  retried POST is a double booking or a double charge — the one thing this
  codebase must not do. Write the reason in the comment; it is the kind of rule
  someone will otherwise "improve" later.
- Both apps — a "the connection is slow, we are still trying" message distinct
  from the existing error state, and a retry affordance on the screens that
  currently dead-end.
- New l10n keys in both catalogues, EN and FR.

**Tests.** ~15 in `shared_client/test/`:
- A request that never completes raises the timeout kind, not a generic error.
- A GET that fails once then succeeds returns the success, and made exactly two
  calls.
- A POST that fails is **not** retried — asserted explicitly, with the call
  count.
- Backoff is respected (fake clock, not a real sleep).
- Widget tests in both apps: the slow-network message appears and the retry
  affordance re-issues the request.

**Done when.** No code path can wait on the network indefinitely, and a flaky
connection produces a message a user can act on.

**Size:** M

---

## Slice 25 — Images sized for the network they cross ❌ → ✅

**Goal.** A browse list of twenty venues pulls tens of kilobytes of thumbnail,
not tens of megabytes of original photograph.

**Why here.** §7.5. Uploads are stored and served at original resolution.
Storage is correctly on R2, so this is not a cost problem — it is the first
impression of the customer app on mobile data, and it undoes the work already
spent making browse feel fast.

**Backend.**
- Generate derivatives on upload: a card thumbnail (~400px wide), a detail
  image (~1200px), keeping the original. Pillow is already a dependency —
  `seed_demo` uses it — so this adds no new runtime dependency.
- Serialize a `thumbnail_url` alongside `image_url` on `Photo` and `MenuItem`.
  Additive: existing clients keep working, which matters because a released
  build cannot be forced to update.
- A management command to backfill derivatives for existing rows, idempotent in
  the house style.
- Cap upload dimensions and re-encode: a 12MP phone photo should not be stored
  as-is.

**Client.**
- Browse cards, menu cards and the dishes feed request `thumbnail_url`; the
  photo viewer and venue header request the full image. The viewer is the one
  place the original is the point.

**Tests.** ~12 backend:
- Uploading generates both derivatives; dimensions are as configured.
- An upload larger than the cap is downscaled, and the stored file is smaller
  than what arrived.
- The backfill command is idempotent and skips rows that already have
  derivatives.
- A row without a derivative still serializes without a 500 — the migration
  window has to be survivable.

**Done when.** The browse list's image payload drops by an order of magnitude,
measured before and after on the seeded database.

**Size:** M

---

## Slice 26 — One status document, and comments that are true ❌ → ✅

**Goal.** A person reading this repository is not misled by it.

**Why here.** §2 and §7.4. `PROJECT_STATUS.md` lists ten priorities of which
**eight have shipped**; anyone planning from it rebuilds finished work. Two
customer-app docstrings state the opposite of what the code now does — *"There
are no customer accounts yet"* and *"Payment is on arrival in the MVP"* — on two
of the most-edited screens. In a codebase whose comments are otherwise reliable,
a false comment does more damage than no comment.

**Repo.**
- Reduce `PROJECT_STATUS.md` to a pointer at `PLATFORM_ASSESSMENT.md`, or delete
  it. Do not maintain both.
- Fix the two stale docstrings (`my_bookings_screen.dart`,
  `booking_form_screen.dart`).
- `README.md` — check its feature list against the audit; it predates six
  phases of work.
- Note the seeded customer logins in the README's testing section, so the next
  person does not have to rediscover them.

**Tests.** None. This is prose.

**Done when.** No document in the repository contradicts the code, and there is
exactly one status document.

**Size:** S

---

## Slice 27 — `main` means what is deployed ❌ → ✅

**Goal.** `main` is a branch someone can deploy from without asking what it is.

**Why here.** §7.6. `main` is **113 commits behind `dev` and 2 commits ahead** —
it has diverged, so the next promotion is a reconciliation rather than a
fast-forward. The release process built in Slice 22 targets `main`, so it
currently targets something 113 slices stale. The divergence only grows.

**Repo.**
- Find out what those two commits are and decide deliberately: cherry-pick onto
  `dev`, or discard them with a note saying why.
- Merge `dev` into `main` and tag it. Per Slice 22's definition, `main` is what
  is deployed.
- Write the promotion ritual into `RELEASE.md` — when `main` moves, who decides,
  and what must be green first.

**Done when.** `git rev-list --count dev..main` is 0, and `main` carries a tag
matching a real deployment.

**Size:** S

---

## Slice 28 — Throttle rates sized on evidence ❌ → ✅

**Goal.** The rate limits reflect observed traffic instead of a guess.

**Why here.** The rates were set deliberately loose and their tuning was
deferred *until throttle-hit metrics existed*. Slice 20 built those metrics, so
this is unblocked and is now a configuration change with a test.

**Backend.**
- Read the throttle-hit counters from the metrics endpoint over a period of
  real use — including a seeded load run if a pilot has not started.
- Tighten `DEFAULT_THROTTLE_RATES` where the ceiling is orders of magnitude
  above observed peak. `booking_phone` and `register` are the two worth being
  strict about: they are where abuse costs money rather than cycles.
- Record the reasoning in the settings comment, in the house style — the next
  person to widen a limit should have to argue with a stated reason.

**Tests.** Extend `test_throttling.py` so each tightened scope has a test
asserting the new boundary. A rate changed without a test is a rate that drifts.

**Done when.** Every rate has either an observation or a stated argument behind
it.

**Size:** S

---

# Phase 8 — Real money, real messages, real push

*Every slice here is **⛔ blocked on something you must obtain**, not on
engineering. The backend for all five is written and tested against stubs. Work
this phase in whatever order the credentials arrive — the slices are independent
of each other apart from 31, which needs 29 or 30.*

**Do not start these before Phase 7.** They are the slices where a bug costs
real money, and Slice 23 is what makes the test suite trustworthy enough to
catch one.

## Slice 29 — Orange Money, for real ⛔ → ✅

**Blocked on:** sandbox credentials and API documentation from Orange Guinea.

**Goal.** A customer pays a deposit with Orange Money and the money arrives.

**Why here.** §8.1. This is the single largest gap between the product and a
pilot that earns. `MockPaymentProvider` already implements the full interface —
`initiate_payment`, `check_status`, `refund` — so the shape of the work is
known: one adapter, one callback endpoint, and the operational care that real
money needs.

**Backend.**
- `payments/providers.py` — `OrangeMoneyProvider(PaymentProvider)`. Auth token
  acquisition and refresh, request signing, their status vocabulary mapped onto
  `Payment.Status`.
- **A callback endpoint**, which the mock never needed: verify the signature,
  treat it as untrusted input, and make it idempotent — a provider will deliver
  the same callback twice and both must be safe.
- Reconcile callback against poll. `poll_pending_payments` already runs every
  30s; a callback should short-circuit it, never contradict it. Where they
  disagree, **the provider's ledger wins and the disagreement is logged loudly**.
- Timeouts and a circuit breaker: a provider outage must not hold a request
  thread or hang a booking.
- Settings: real credentials via `config()`, never committed. `PAYMENT_PROVIDERS`
  maps `orange_money` to the real class in production and the mock everywhere
  else — the switch stays a settings change, as designed.

**Tests.** ~30, all against recorded fixtures, never the live sandbox:
- Each provider status maps to the right `Payment.Status`.
- A duplicate callback is a no-op.
- A callback with a bad signature is refused and logged.
- Provider timeout leaves the payment `pending`, not `failed` — the money may
  still be moving, and calling it failed is how a customer gets charged for a
  booking they were told they did not get.
- A payment completing between two polls confirms the booking exactly once.
- Manual sandbox verification is a checklist in the PR, not an automated test.

**Done when.** A real sandbox payment moves a booking to confirmed without
anyone watching, and the same flow still works against the mock in tests.

**Size:** L

---

## Slice 30 — MTN Mobile Money ⛔ → ✅

**Blocked on:** MTN sandbox credentials.

**Goal.** The same, for the other half of the market.

**Why here.** Second because the first adapter discovers the shape of the
abstraction, and the second either confirms it or corrects it cheaply. Doing
both at once means designing the interface twice with no feedback.

**Backend.** `MtnMoneyProvider` behind the same ABC. Expect the differences to
be in status vocabulary and callback authentication; expect to adjust the
`PaymentProvider` interface once, and let that adjustment be the deliverable of
this slice as much as the adapter is.

**Tests.** ~25, mirroring Slice 29, plus one asserting both providers satisfy
the same contract — a shared test body run against each.

**Size:** M

---

## Slice 31 — Reconciliation a merchant can argue with ⛔ → ✅

**Blocked on:** 29 or 30.

**Goal.** When a customer says "I paid" and the dashboard says otherwise,
someone can settle it in a minute.

**Why here.** The payments dashboard was built for this argument, and
`reservation_detail_screen.dart` already exposes copyable references. What is
missing is the provider's side of the ledger to compare against.

**Backend.**
- A daily reconciliation task: fetch the provider's settled transactions, match
  on `provider_reference`, and record the mismatches rather than silently
  correcting them. **A mismatch is a fact to be reviewed, not a bug to be
  auto-fixed** — the auto-fix is how money quietly disappears.
- A `PaymentDiscrepancy` record: what we hold, what they hold, when it was
  noticed, whether it was resolved.
- Surface unresolved discrepancies on the payments dashboard.
- Refunds end to end: the interface exists and the mock implements it; make it
  real, and decide who may trigger one (owner only, matching staff CRUD).

**Tests.** ~20: a missing local payment, a missing remote payment, an amount
mismatch, a duplicate reference, and a refund that the provider refuses.

**Done when.** A merchant can be told, with evidence, where a specific 50,000
GNF is.

**Size:** M

---

## Slice 32 — SMS that leaves the machine ⛔ → ✅

**Blocked on:** D4 — which aggregator.

**Goal.** A reminder and a reset code reach a phone.

**Why here.** §8.1. `ConsoleSmsNotifier` prints; `NOTIFIERS['sms']` is one
setting away from a real class. Reminders, no-show warnings and password resets
are all written and all currently shout into a terminal.

**Backend.**
- One `Notifier` implementation for the chosen aggregator.
- Delivery receipts where the aggregator offers them, recorded on
  `Notification` — which already has `status` and `error` fields waiting.
- Retry with backoff on transient failures; give up loudly, never silently.
- **Cost control**: a per-recipient daily cap. SMS costs money per message, and
  a retry loop with a bug is a bill.

**Tests.** ~15 against a fake gateway: success, hard failure, transient failure
then success, cap enforcement, and a code that is never logged in plaintext.

**Done when.** A booking made now produces a reminder on a real handset at the
right time, and never at 04:00 — `reminders.py` already guarantees the second
part.

**Size:** M

---

## Slice 33 — Push on the phone ⛔ → ✅

**Blocked on:** a Firebase project and a service account.

**Goal.** A merchant learns about a booking without opening the app.

**Why here.** §7.3. This is the most lopsided item in the repository: the
server half is **complete** — `DeviceToken`, `POST /api/devices/`,
`FirebasePushSender` behind a setting, `ConsolePushSender` keeping the path
exercised — and the client half does not exist at all. Neither app carries a
Firebase dependency; `venue_desk_screen.dart:46` says so in a comment.

**Client.**
- Firebase to both apps; request permission at a moment that makes sense (after
  the first booking, not on first launch — a permission prompt before any value
  is refused and never asked again).
- Register the token against `POST /api/devices/`, re-register on refresh, and
  unregister on sign-out. A stale token pushes a merchant's bookings to a phone
  they no longer use.
- Foreground, background and cold-start handling, with a tap opening the booking
  or order it names.

**Backend.** Flip `PUSH_SENDER` to `FirebasePushSender`; prune tokens Firebase
reports as unregistered — `push.py` already distinguishes rejected from failed
for exactly this.

**Tests.** Client: registration on sign-in, unregistration on sign-out, tap
routing. Backend push tests exist already.

**Done when.** A booking made in the customer app raises a notification on the
merchant's phone with the app closed.

**Size:** M

---

# Phase 9 — What a merchant will ask for next

*The first pilot venue will ask for these in roughly this order. All three are
unblocked, and every number they need is already in the database.*

## Slice 34 — Analytics a merchant recognises ❌ → ✅

**Goal.** A merchant opens the app and learns something about their business
they did not already know.

**Why here.** §9. The highest-value new merchant feature, and the payments
dashboard is the pattern to copy — including its discipline of showing money as
strings and never inventing precision.

**Backend.** A `merchant/establishments/<pk>/insights/` endpoint:
- **Covers per service**, by day and by day-of-week — the number a restaurant
  actually plans staff against.
- **No-show rate**, lapsed and late-cancelled shown separately (**D6**).
- **Popular dishes** by quantity and by revenue — they rank differently, and the
  difference is the insight.
- **Repeat customers**: how many bookings come from someone who has been before.
  `Reservation.customer` makes this a query now that accounts exist.
- **Peak hours** from booking datetimes.
- All windowed (7 / 30 / 90 days), all scoped by membership like every other
  merchant route.

**Client.** An Insights destination in the merchant app. Charts must survive
being read on a phone in a dark lounge: large type, few series, no colour-only
encoding. Empty states that say *why* a number is empty — a venue with no
completed sittings has no no-show rate, and that is not an error.

**Tests.** ~25 backend, covering the arithmetic against a known fixture, the
window boundaries, and membership scoping. Widget tests at 360×900 and tablet.

**Done when.** A merchant can answer "which night is worth opening for" from the
app.

**Size:** L

---

## Slice 35 — Kitchen tickets on paper ❌ → ✅

**Goal.** An order prints in the kitchen.

**Why here.** The queue, the stages and the walk-in flow all exist; this is a
printer adapter and a layout. It moves down the order because a screen in the
kitchen works, and paper is a preference until a venue says otherwise.

**Client.** ESC/POS over Bluetooth or network, behind an interface with a
console implementation — the same shape as `Notifier`, `PushSender` and
`PaymentProvider`, and for the same reason. Ticket layout: order reference,
time, items, quantities, notes. Reprint, because tickets are lost.

**Backend.** Nothing, unless auto-print on placement is wanted, which needs a
per-venue setting.

**Tests.** Layout rendering against a fake printer; reprint produces the same
bytes.

**Size:** M

---

## Slice 36 — Getting the numbers out ❌ → ✅

**Goal.** A merchant can hand their accountant a file.

**Why here.** Cheap once Slice 34 exists — the queries are written; this is a
serializer and a share sheet.

**Client / Backend.** CSV export of payments and bookings for a date range,
delivered through the platform share sheet. Owner and manager only.

**Tests.** ~8: correct rows, correct scoping, a range with no data, and
characters that break naive CSV (a venue called "Chez Sory, Kaloum").

**Size:** S

---

# Phase 10 — Fit for the market it is built for

*These are the slices that distinguish a product built for Conakry from one
built anywhere and shipped there.*

## Slice 37 — A third language ❌ → ✅

**Blocked on:** D5, and a translator.

**Goal.** The app speaks the language its users speak at home.

**Why here.** §8.2. EN and FR are done and the machinery is proven with two
complete catalogues — `compile_po`, `msgctxt` contexts, a test that fails if the
`.mo` drifts from the `.po`. A third catalogue is translation work, not
engineering, and it is a genuine differentiator against anything imported.

**Repo.** A third `.arb` per app and a third Django catalogue. Budget for the
fact that status words need contexts in any language, and that a translator will
need the same context notes the French catalogue carries.

**Tests.** The existing catalogue-completeness tests extend to the third
language for free — they are written against the key set, not against French.

**Size:** M — mostly waiting on translation.

---

## Slice 38 — Usable on a bad connection ❌ → ✅

**Goal.** A merchant on the floor with one bar can still see tonight's list.

**Why here.** §8.3. Slice 24 stops the app hanging; this one lets it still be
useful. Favourites already prove the pattern — optimistic, offline-tolerant,
reconciled later. Deliberately after Phase 8: caching a payment state is a
harder question than caching a list, and it should be designed once the real
provider's timing is known.

**Client.**
- Cache the merchant's day and the customer's bookings locally; show them with a
  visible "last updated" rather than pretending they are live.
- Queue confirm/cancel actions taken offline and replay them on reconnect, with
  an explicit conflict rule: **the server wins, and the merchant is told what
  changed under them.**
- Never queue a payment. Same rule as retrying a POST, same reason.

**Tests.** ~20: cache hit renders with its timestamp, a queued action replays
once, a conflict surfaces rather than silently losing, and a payment is never
queued.

**Size:** L

---

## Slice 39 — Links that open the right thing ❌ → ✅

**Goal.** The reminder SMS from Slice 32 contains a link that opens the booking.

**Why here.** Directly after SMS becomes real, because that is what makes deep
links worth having.

**Client.** Deep links to a booking, an order and a venue. The reference is
already the credential, so a link carrying one needs no new auth model — but it
does need the same care: a link is shoulder-surfable, so it opens a booking, not
an account.

**Backend.** Include the link in reminder and confirmation messages. A shareable
venue link for merchants to post is a small addition here.

**Tests.** ~10: each link type routes correctly, an unknown reference fails
gracefully, and a link never signs anyone in.

**Size:** M

---

# Phase 11 — Growth

*Market-report Phase 3+. Reorder freely against what pilot venues actually ask
for — that feedback is worth more than this ordering.*

| Slice | Feature | Notes |
|---|---|---|
| 40 | **Loyalty** — priority booking for regulars (**D8**) | Needs the stable customer identity from Slice 18 and the repeat-customer query from Slice 34 |
| 41 | **Inventory** | Extends `MenuItem.is_available` from a boolean to a count; the sold-out flow already exists as the UI |
| 42 | **WhatsApp fallback** | Another `Notifier` implementation — the interface fits, which is the whole argument for having built it that way |
| 43 | **Waiting lists / overbooking** | Touches `availability.py`, the best-tested code in the repository. Do not attempt before Phase 7 restores CI |
| 44 | **Map view of results** | Distance is already computed and sortable; venues are simply never plotted |
| 45 | **Receipts** | A customer-facing artefact for a booking or order; trivial once Slice 36's export exists |

---

## What this adds up to

**Phase 7 is one week and should start now.** It costs less than any other phase
and it repairs the instrument — a CI pipeline that is red most of the day — that
every later phase is verified with. Slices 24 and 25 also happen to be the two
most user-visible improvements available at any price.

**Phase 8 is the pilot.** Nothing in it can start until credentials arrive, and
nothing else in this plan needs them. The correct move is to chase those
credentials in parallel with Phase 7 rather than sequentially — the engineering
is ready and waiting on paperwork.

**Phase 9 is what keeps a pilot venue.** A merchant who can see their own
numbers renews; one who cannot compares the app to a notebook and finds the
notebook cheaper.

**Phases 10 and 11 are the product's second year.** They are listed so the
shape is visible, not because the order is settled. Rewrite them the day a real
venue in Conakry tells you what they actually want — as the first version of
this plan said, and it was right.
