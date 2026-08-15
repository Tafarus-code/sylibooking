# Demo accounts

Every login in a database seeded by `seed_demo`. Generated data only — these
accounts exist to demo and test against, and the password below is public in
this repository, so **nothing here belongs on a database holding real
bookings or real customers.**

```
python manage.py seed_demo
```

Additive and idempotent: a venue or username that already exists is left
alone, so running it twice is safe and it never touches data you created by
hand. The command prints this same list at the end of a run — this file is
for when you need it without running anything.

## The password

**`sylibooking`** — for every account below, merchant and customer alike.

Override it at seed time if the database will be reachable by anyone else:

```
python manage.py seed_demo --password 'something-else'
```

The password is only ever set on accounts the seeder *creates*. Change it
afterwards and re-running `seed_demo` will not put it back.

## Merchant logins

Three accounts per venue, one for each role. The username is the venue name
lowercased with spaces, apostrophes, accents and `&` removed, cut to 14
characters — predictable on purpose, so a venue you are looking at is a venue
you can log into.

| Role | Username | What it can do |
|---|---|---|
| Owner | `<venue>` | Everything, including who else has access |
| Manager | `<venue>.mgr` | Everything except adding or re-roling members |
| Staff | `<venue>.staff` | The floor: bookings, confirmations, orders |

The lines are drawn in `MerchantMembership` (`establishments/models.py:354`):
managing members is owner alone; editing the venue's profile — hours, menu,
photos, spaces — is owner and manager; refunding a deposit is owner and
manager too, because giving money back is a decision about the takings rather
than a floor call. Running the floor is all three.

### Restaurants

These carry the menu and the kitchen queue; ordering is restaurant-only by
rule, so a lounge has neither.

| Venue | Where | Owner login |
|---|---|---|
| Le Damier | Kaloum, Conakry | `ledamier` |
| Chez Mariama | Dixinn, Conakry | `chezmariama` |
| Le Baobab Doré | Ratoma, Conakry | `lebaobabdore` |
| Terrasse du Niger | Matam, Conakry | `terrassedunige` |
| Maquis Kaloum | Matoto, Conakry | `maquiskaloum` |
| La Paillote | Kipé, Conakry | `lapaillote` |
| Saveurs du Fouta | Lambanyi, Conakry | `saveursdufouta` |
| Le Petit Marché | Labé Centre, Labé | `lepetitmarche` |
| Riz & Sauce | Daka, Labé | `rizsauce` |
| Chez Sory | Kaloum, Conakry | `chezsory` |
| Le Wharf | Dixinn, Conakry | `lewharf` |

### Lounges

| Venue | Where | Owner login |
|---|---|---|
| Le Petit Baobab | Ratoma, Conakry | `lepetitbaobab` |
| Sky Lounge Kipé | Matam, Conakry | `skyloungekipe` |
| Le Nimba | Matoto, Conakry | `lenimba` |
| Villa 224 | Kipé, Conakry | `villa224` |
| Le Cocotier | Lambanyi, Conakry | `lecocotier` |
| Bissap Lounge | Labé Centre, Labé | `bissaplounge` |
| La Terrasse Dixinn | Daka, Labé | `laterrassedixi` |
| Nuit Blanche | Kaloum, Conakry | `nuitblanche` |
| Le Salon Rouge | Dixinn, Conakry | `lesalonrouge` |
| Kaloum Nights | Ratoma, Conakry | `kaloumnights` |
| Le Hangar | Matam, Conakry | `lehangar` |

Note the two truncations, which are the only usernames you cannot guess from
the venue name alone: **`terrassedunige`** (Terrasse du Niger) and
**`laterrassedixi`** (La Terrasse Dixinn).

### A worked example

Le Damier's three logins are `ledamier`, `ledamier.mgr` and `ledamier.staff`,
all with the password above. Signing in as `ledamier.staff` is the quickest
way to see what a role refuses: the spaces, menu and staff screens are gone,
and the booking desk is not.

## Customer logins

Four accounts, differing in what contact details they carry — the app behaves
differently for each, which is the point of having four.

| Username | Name | Phone | Email |
|---|---|---|---|
| `mariama` | Mariama Diallo | +224620111222 | mariama.diallo@example.gn |
| `sekou` | Sékou Camara | +224621333444 | — |
| `kadiatou` | Kadiatou Barry | — | kadiatou.barry@example.gn |
| `binta` | Binta Sow | — | — |

`binta` is deliberate: with neither a phone number nor an email there is no
way to send a reset code, so this is the account the app warns about — the one
that would be lost with the handset. Use it to check that warning still shows.

Each seeded customer gets favourites and a booking history, so Favourites and
History open on a list rather than an empty state.

## The admin

`seed_demo` creates **no superuser** — an admin account with a known password
is not something to generate. Make your own:

```
python manage.py createsuperuser
```

## What else is in there

By default the seeder also lays down six months of trading behind today
(`--months 6`, `0` to skip): past bookings, orders, payments and reviews,
weighted so Fridays and Saturdays are busier than Mondays, with some
customers returning. That history is what the insights screen's 90-day
window, the payments dashboard and the CSV export are read against — seeded
with zero months they all come back empty and correct, which looks like a
bug.
