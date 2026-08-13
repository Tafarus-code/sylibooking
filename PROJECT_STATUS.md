# Sylibooking — Project Status

**This file is no longer maintained. See
[`PLATFORM_ASSESSMENT.md`](PLATFORM_ASSESSMENT.md).**

---

## Why it was retired

This was an audit written on 2 August 2026. By 12 August, **eight of the ten
priorities in its "what to improve, in order" list had shipped** — `Space`
management, venue self-registration, the reservation lifecycle, deposits,
review moderation, walk-in orders, the async layer, pagination, observability
and deployment.

Anyone planning from it would have rebuilt finished work, and at least one
person did start to. A status document that is wrong is worse than none: it is
trusted in exactly the way an empty file is not.

It was replaced rather than corrected because two status documents drift apart
again the moment one of them is easier to update. There is now one, and this
pointer exists so an old link still lands somewhere true.

## Where things are now

| Question | Answer |
|---|---|
| What is built, and what is missing? | [`PLATFORM_ASSESSMENT.md`](PLATFORM_ASSESSMENT.md) |
| What is being built next, in what order? | [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) — slices 1–22 are the record, 23 onward is the plan |
| How do I run it, and what are the test logins? | [`README.md`](README.md) |
| How does a release happen? | [`RELEASE.md`](RELEASE.md) |
| How is it deployed? | [`deploy/README.md`](deploy/README.md) |

The original text is in the history if it is ever wanted:
`git show 170a0a0:PROJECT_STATUS.md`.
