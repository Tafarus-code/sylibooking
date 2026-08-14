# Releasing Sylibooking

## What the branches mean

| Branch | Means |
|---|---|
| `feat/*`, `fix/*`, `chore/*` | One slice of work. Merged to `dev` once its own CI is green. |
| `dev` | Everything finished. Always green, not necessarily deployed. |
| `main` | **What is deployed.** Nothing reaches it except a deliberate promotion. |

`main` is not "the latest good code" — `dev` already is that, and a branch
whose meaning is "probably fine" tells nobody anything. `main` answers one
question: *what is running in Conakry right now.* That makes it useful during
an incident, which is the only moment anybody needs to ask.

Two consequences worth stating, because they look like problems and are not:

- **`main` will usually be behind `dev`, sometimes far behind.** That is the
  point. Distance is a measure of what is finished but not yet released, not
  a measure of neglect.
- **Nothing is merged to `main` automatically.** Promotion is a decision
  someone makes, not something that happens because tests passed.

## Who decides, and when

**One person decides, and it is whoever will answer the phone if it breaks.**
Not the person who wrote the slice, and not "CI is green so ship it" — green is
a precondition, never a reason.

`main` moves when there is something worth a real venue's attention, not on a
calendar. In practice that is: a feature a merchant asked for, a fix for
something they hit, or a security fix — which goes on its own, immediately,
rather than waiting for company.

Do not promote on a Friday, or in the evening in Conakry. A lounge takes its
bookings between 19:00 and 02:00, and that is exactly when nobody wants to be
reading a stack trace. Promote in the morning, on a day where the afternoon is
free to undo it.

### Before promoting

Every one of these, in order. The first four are cheap and the last one is the
one people skip.

1. **CI green on `dev`** — all six jobs, on the commit being promoted, not on
   one that looks close enough.
2. **Migrations reviewed**, not just present. `python manage.py migrate --plan`
   against a copy of production. A migration that rewrites a large table is a
   deploy decision, not a detail.
3. **Data steps identified.** Some slices need a command run *after* the code
   is up — `backfill_image_copies` is the current example, and it is safe to
   run twice but useless if it is never run at all. List them in the release
   message so the next person can see what was done.
4. **The app in the field still works against the new server.** Every API
   change since the last tag has to be additive, because a phone in Labé
   updates when its owner decides to. If something had to change shape, the
   old shape stays until the installed base has moved.
5. **Someone has actually used it.** Book a table, take an order, mark a guest
   arrived, against the build being promoted. The suite proves the parts; this
   proves the evening.

## Promoting

```
git checkout main
git merge --no-ff dev -m "Release vX.Y.Z: <what changed for whoever uses it>"
git tag -a vX.Y.Z -m "<the same summary>"
git push origin main --follow-tags
```

The tag is what makes "what is running" answerable months later, when the
branch has moved on and the question is about a night in August.

**If it goes wrong**, roll forward rather than back where you can — `main`
moving backwards makes "what is deployed" unanswerable, which is the one thing
this branch exists to answer. Where a rollback is genuinely the only option,
redeploy the previous tag and say so in the next release message. A migration
that has already run is the case that decides this: code can go back, an
altered table usually cannot.

Versions are `MAJOR.MINOR.PATCH` against what a *user* notices, not what the
code did:

- **PATCH** — fixes only. Nobody has to be told anything.
- **MINOR** — something new that a merchant or customer will see.
- **MAJOR** — a change that breaks somebody's habit, or an API the apps in
  the field already depend on.

That last one matters more here than usual: an app installed on a phone in
Labé updates when its owner decides to, over a connection they pay for. The
server has to keep answering the version already out there.

## Store builds

Both apps build from the same command; only the flavour of what is signed
differs.

```
cd apps/merchant_app     # or customer_app
flutter build appbundle --release
```

The bundle lands in `build/app/outputs/bundle/release/`.

### The upload key

`android/key.properties` and the keystore beside it are git-ignored and must
stay that way. See `android/key.properties.example` for how to generate one.

**Back it up somewhere you will still have in five years.** Google Play will
not accept a different key later without a reset request, and losing it means
losing the ability to update an app people already have installed. This is the
single most irreversible thing in the project.

Without `key.properties`, a release build comes out **unsigned** rather than
falling back to the debug key. That is deliberate. A debug-signed release
installs and runs perfectly, so the mistake is invisible right up until Play
rejects it — or worse, does not, and the app can never be updated from a
machine that lacks the same debug keystore.

## Still to do

- **The Play Store listing** — screenshots, description, privacy policy, and
  a data-safety declaration. That last one has to match what the apps
  actually collect: a name, a phone number, and optionally an email, with
  crash reports only after an explicit yes (see `crash_reporting.dart`).
- **Push notifications**, which need a Firebase project. Slice 7's
  notification log already records what would be sent; push is what turns
  that into something a merchant sees without opening the app.
