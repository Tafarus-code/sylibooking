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

## Promoting

```
git checkout main
git merge --no-ff dev -m "Release vX.Y.Z: <what changed for whoever uses it>"
git tag -a vX.Y.Z -m "<the same summary>"
git push origin main --follow-tags
```

The tag is what makes "what is running" answerable months later, when the
branch has moved on and the question is about a night in August.

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
