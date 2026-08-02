# Sylibooking — Implementation Plan

**Written 2 August 2026**, from the audit in [`PROJECT_STATUS.md`](PROJECT_STATUS.md).
Covers everything that document marks 🟡 stubbed, 🔶 backend-only, ❌ missing,
or listed as a defect — plus the improvement suggestions, sequenced.

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
| D2 | **How long after its time a booking is a no-show.** | Slice 4, 5 | **90 minutes**, configurable per venue later. A lounge table is not lost at minute 16. |
| D3 | **May staff edit tables/rooms, or owners and managers only?** | Slice 1, 2 | **Owners and managers**, matching hours and menu editing. Staff already mark items sold out; spaces are structural. |
| D4 | **Which SMS aggregator.** | Slice 9 | Needs a local quote — this is a commercial choice, not a technical one. The `Notifier` interface is already in place, so the code cost is one adapter whichever you pick. |

Two more will come up later and can wait: whether merchants may hide reviews or
only flag them (Slice 13), and where this is hosted (Slice 20).

---

## Sequencing at a glance

```
Phase 0  Unblock the MVP          Slices 1–3    ← nothing real can happen without this
Phase 1  Close the lifecycle      Slices 4–5    ← stops the data telling a lie
Phase 2  The async layer          Slices 6–8    ← retrofitting later touches every write path
Phase 3  Real money               Slices 9–12
Phase 4  Merchant completeness    Slices 13–15
Phase 5  Correctness and polish   Slices 16–18
Phase 6  Operability              Slices 19–21
Phase 7  Beyond the MVP           Slices 22+
```

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
- **Automatic lapse.** A confirmed booking whose time passed by more than the
  no-show window (**D2**) and was never marked arrived becomes `no_show` — a
  new status, distinct from `completed`, because the two mean opposite things
  commercially and Slice 5 needs to tell them apart. Implemented as a
  management command now, moved onto the scheduler in Slice 7.
- `backend/reservations/availability.py` — `no_show` releases the slot;
  `completed` continues to hold it.

**Client.**
- Merchant: a "Mark arrived" action on the reservation card and detail screen,
  visible only for a confirmed booking whose time has come.
- Customer: past bookings read "Completed" or "Missed" rather than sitting on
  "Confirmed" forever.
- Both catalogues.

**Tests.** ~25 backend: the action's role gating; refusing to complete a
future or cancelled booking; the lapse command's boundary at exactly the
window; a no-show releasing its slot; a completed booking still holding it;
idempotency when the command runs twice. Plus widget tests both sides.

**Done when.** A day's bookings can be worked to a conclusion, and yesterday's
data is a true record.

**Size:** M

---

## Slice 5 — Deposits mean something ❌ → ✅

**Goal.** The 50,000 GNF taken from a mobile money booking has a defined fate.

**Why here.** §9.4. The deposit is charged and then nothing happens to it. It
is the commercial point of taking one, and it depends on Slice 4 being able to
tell a no-show from a completed visit.

**Blocked on D1 and D2.** Written below for my recommendation — offset on
arrival, forfeit on no-show.

**Backend.**
- `backend/payments/models.py` — `Payment.outcome`: `offset`, `forfeited`,
  `refunded`, `none`. The deposit stays `completed` as a *payment*; its
  outcome is a separate axis.
- `backend/payments/services.py` — `settle_deposit(reservation)`, called when a
  booking completes (offset) or lapses to no-show (forfeit).
- A refund path on the provider interface — `PaymentProvider.refund()` — even
  though the mock is the only implementation until Slice 9. Designing it now
  keeps Slice 9 from being an interface change as well as an adapter.
- Dashboard: forfeited deposits are revenue and belong in the totals; offset
  ones are not, and double-counting them would overstate takings.

**Client.**
- Customer: the booking screen says plainly what happens to the deposit before
  it is taken, and the confirmation repeats it. This is the sentence that
  decides whether deposits get accepted in the market at all — worth writing
  carefully in both languages.
- Merchant: the reservation detail shows the deposit's outcome, and the
  payments dashboard separates forfeited from collected.

**Tests.** ~20: each transition; a cash booking having no deposit to settle;
settling twice being a no-op; the dashboard's arithmetic under a mix.

**Done when.** Every deposit taken has an outcome, and the dashboard's total
is defensible to a merchant counting cash.

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
- `docker-compose.yml` for a local Redis — the first piece of Slice 20.
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
needs Firebase and a signing story, which is Slice 21.

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
as it will against a real provider, so Slice 9 inherits a working poller.

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

## Slice 10 — Orange Money, sandbox 🟡 → ✅

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

## Slice 11 — MTN Mobile Money ✅

Same shape as Slice 10 against a second API. Cheaper — the callback pattern,
the retry policy and the tests are established. **Size:** M

---

## Slice 12 — Reconciliation and refunds 🟡 → ✅

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

## Slice 13 — Merchants can see their reviews 🔶 → ✅

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

## Slice 14 — Walk-in orders ❌ → ✅

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

## Slice 15 — Pagination in the merchant app ❌ → ✅

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

## Slice 16 — The visible defects ✅

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

## Slice 17 — Customer profile and account deletion ❌ → ✅

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

## Slice 18 — Rate limiting and abuse ❌ → ✅

**Goal.** Login, registration, password reset and booking creation cannot be
hammered.

**Why here.** §9.6. The per-code attempt cap exists; nothing else does.
Booking creation is unauthenticated by design, which is correct and also an
open door.

**Backend.** DRF throttling, tighter on the auth and reset paths, plus a
per-phone cap on bookings in a window.

**Tests.** ~12, including that a throttled response is a clean 429 the apps
render as a message rather than a crash.

**Size:** S–M

---

# Phase 6 — Operability

## Slice 19 — Observability ❌ → ✅

**Goal.** When something breaks in Conakry, you find out from a dashboard
rather than from a merchant.

**Backend.** Structured logging, an error reporter (Sentry or equivalent), a
health endpoint, and metrics on the numbers that matter: bookings created,
payments initiated versus completed, notification delivery rate. **Slice 7's
notification log and Slice 12's reconciliation are the two places where silent
failure is most expensive**, so instrument those first.

**Client.** Crash reporting in both apps, behind a consent line.

**Size:** M

---

## Slice 20 — Deployment ❌ → ✅

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

## Slice 21 — Release process and push ❌ → ✅

- `main` is many slices behind `dev` and has never been merged. Define what
  `main` means — I suggest "what is deployed" — and merge to it deliberately,
  with a tag.
- Store builds, signing keys, and a Play Store listing.
- Push notifications (Firebase), which turns Slice 7's alerts into something a
  merchant sees without opening the app.

**Size:** L

---

# Phase 7 — Beyond the MVP

Phase 3+ of the market report. Listed in the order the earlier work makes them
cheapest, not in order of appeal.

| Slice | Feature | Why it is cheap now |
|---|---|---|
| 22 | **Kitchen tickets / printing** | The queue and stages exist; this is a printer adapter and a layout |
| 23 | **Analytics for merchants** — covers per night, turnover, popular dishes, repeat customers | The data is all there; the payments dashboard is the pattern to copy |
| 24 | **Loyalty** | Needs Slice 17's stable customer identity, which is why it is not earlier |
| 25 | **Inventory** | Extends `MenuItem` availability from a boolean to a count |
| 26 | **WhatsApp fallback** | Another `Notifier` implementation; the interface already fits |
| 27 | **Waiting lists / overbooking** | Needs the availability engine, which is the best-tested code in the repo |

---

## What this adds up to

Phases 0 and 1 — five slices — are the difference between what exists and a
product a real merchant in Conakry can use with real customers, on mock money.
That is the shortest path to something worth showing.

Phases 2 and 3 — seven more — are the difference between that and taking
actual payments reliably.

Everything from Phase 4 on improves a working, earning product, and can be
reordered freely against what the first pilot venues actually complain about.
That feedback is worth more than this document's guesses, and this plan should
be rewritten the day it arrives.
