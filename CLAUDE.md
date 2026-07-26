# Sylibooking — Project Brief

## What this is
A reservation + management platform for hookah lounges **and restaurants** in Guinea (Conakry first, then Labé). Two apps sharing one backend:
- **Customer app** — discover establishments, reserve a table/room, pay
- **Merchant app** — manage availability, reservations, orders, payouts

Full context lives in `Sylibooking_Rapport_Etude_Marche.docx` (market research, full feature list, phased roadmap). This file is the *build* brief — narrower on purpose.

## MVP scope — build this first, nothing else
One flow, end to end, before anything fancier:

1. Merchant registers an establishment (lounge or restaurant), adds tables/rooms, sets opening hours
2. Customer browses establishments and sees real availability for a date/time
3. Customer books a slot — payment is "pay on arrival" only at first, no mobile money yet
4. Merchant sees the reservation on a calendar/list and can confirm or cancel

Everything else — mobile money, deposits/no-show handling, loyalty, kitchen tickets, inventory, WhatsApp fallback, analytics — comes **after** this loop works. Resist the urge to build it all at once; the market report's Phase 1 already trims scope, this trims it further for the first working version.

## Tech stack
- **Backend:** Django + Django REST Framework, PostgreSQL
- **Mobile:** Flutter — two separate apps (customer, merchant) sharing a small internal Dart package for API models/client
- **Async tasks:** Celery + Redis for reminders/notifications — stub these for MVP (just log, don't send)
- **Payments:** Orange Money / MTN Mobile Money APIs — build against a mock provider first; wire the real sandbox once the reservation flow is solid
- **SMS:** any local gateway later; stub as console/log output for now

## Suggested repo layout
```
sylibooking/
  backend/
    config/                 # Django settings
    establishments/         # Establishment, Space models
    reservations/           # Reservation model, availability logic
    payments/                # Payment model + provider adapters (mock first)
    api/                     # DRF serializers/viewsets, urls
  apps/
    customer_app/            # Flutter
    merchant_app/            # Flutter
    shared_client/           # shared Dart package: API client + models
```

## Core data models — start here
- **Establishment**: name, type (`lounge` | `restaurant`), city, address, geo, opening_hours
- **Space**: belongs to Establishment — table/room, capacity, type (table, VIP room, terrace)
- **Reservation**: space, customer, datetime, party_size, status, deposit_amount, payment_status
- **User**: customer or merchant staff, role
- **Payment**: reservation, provider, amount, status, provider_reference

Keep `type` (lounge vs restaurant) as a plain field on Establishment, not a fork in the data model — both share the same reservation core. The kitchen-ticket/order flow for restaurants is an addition on top of Reservation later (an Order model linked to a Reservation or a walk-in table), not a parallel system.

## Build order
1. Django models + admin panel — lets you create test establishments/spaces by hand before any app exists
2. DRF API: list establishments, get availability for a date, create a reservation
3. Merchant app: login, view today's/week's reservations, confirm or cancel
4. Customer app: browse establishments, pick a slot, reserve (pay-on-arrival only)
5. Once that loop works end-to-end with real test data: add mobile money (sandbox), then deposits/no-show handling
6. Only after that: loyalty, inventory, kitchen tickets, WhatsApp fallback, analytics — per the phased plan in the market report

## Working with Claude Code on this
- Start a git repo before writing anything; commit after each working slice (models → migrations → admin → API → one screen), not at the end of the day
- Ask Claude Code to scaffold one layer at a time — e.g. "create the Django models for Establishment, Space, and Reservation with an admin.py registering them" — rather than "build the backend"
- Ask for tests alongside each piece (model constraints, one API test per endpoint) so the reservation logic (double-booking, availability windows) doesn't silently break as features get added
- Don't start the merchant and customer apps in parallel — get the merchant side seeding real availability first, since there's nothing for a customer app to book against otherwise
- Don't integrate real Orange Money/MTN endpoints until the reservation flow works without them; a mock payment provider (always returns "success") is enough to build and demo the whole flow
