# ELI5: What This Demo Is

> Simplified from: README.md, docs/BOUNDARIES.md, docs/TEST_EVIDENCE.md

## One-Sentence Version

A record label's staff can ask questions about money and streaming in plain
English, and the system physically cannot show any one person data they are not
allowed to see.

## The Story

Picture a big office building shared by 75 small record labels. Each label has a
filing room full of paperwork: monthly money statements, and daily logs of how many
times each song was played.

Normally, if you want a number, you ask an analyst. They walk to the filing rooms,
pull the right folders, do the math, and come back. That takes a day or two. So this
demo puts a clerk at the front desk who you can just talk to. You ask "how much of
last year's Amazon money came from this song," and the clerk fetches it.

The interesting part is not the clerk. It is the door locks. Every filing room has a
lock, and your badge only opens the rooms your label owns. The clerk carries **your**
badge, not a master key. So when you ask about a room you cannot enter, the clerk
comes back and says "you are not allowed in there" — it does not quietly report that
the room was empty. That difference is the whole point of the demo.

One more detail that matters. The money paperwork and the play-count logs are kept in
two separate filing rooms, written by two different departments, on two different
schedules. The clerk is not allowed to combine them into one number, because the
totals would not honestly line up. It can read you both, side by side, but it will
refuse to divide one by the other.

## The Cast

- **Cortex Agent** — the clerk at the front desk. Takes your plain-English question,
  decides which filing room to visit, and reports back.
- **Semantic view** — the label on each filing cabinet, written in human words. It
  tells the clerk that "revenue" means this specific column, in dollars, after
  deductions. Without it the clerk would have to guess.
- **Row access policy** — the door lock. It checks who is asking and hides every row
  they are not entitled to. It lives on the data itself, not on the clerk.
- **Entitlement table** — the badge system. A list of who is allowed into which rooms,
  and for which kind of paperwork. Someone can be allowed to see a label's money and
  still not be allowed to see its play counts.
- **Persona** — a pretend employee used for the demo. Three of them: one who can see
  everything, one who can see three labels, and one who can see nothing.
- **CoWork** — the room where you talk to the clerk. It matters because it tells the
  clerk who you really are.
- **Reference queries** — a second set of books. Someone worked out every answer by
  hand, the slow way, before the clerk existed. If the clerk and the hand-written
  answer disagree, the hand-written one wins until proven otherwise.

## What Changed

- **Before:** ask an analyst, wait a day. **After:** ask in plain English, get an
  answer in under a minute.
- **Before:** "revenue" might mean three different things depending on who ran the
  report. **After:** one definition, written down, stated in every answer.
- **Before:** access control depended on whoever built the report remembering to
  filter it. **After:** the lock is on the data, so forgetting is not possible.
- **Before:** a missing week of data looked like a week of zero activity on a chart.
  **After:** it shows as a gap, and the system tells you how many days were actually
  reported.

## What to Watch Out For

**This is a demo, not a finished product.** The locks are real, but who holds which
badge is set up by hand. In production, the badge list has to be kept in sync with
the company's real permission system — and the hard part is not granting access, it
is removing it fast enough when someone's permission is taken away.

**The biggest risk is one shared badge.** If an app calls the clerk using a single
service account for everybody, then everyone inherits that account's access and every
guarantee here stops being true. The clerk has to carry the actual person's badge.

**Conversation history is another copy of the data.** Past chats and any saved results
need the same locks as the filing rooms. That was not built and not tested here.

**It is not plugged into Backstage.** Backstage is the label's own internal system, and
the original ask was to put this chat inside it. That user interface does not exist
here. What exists is the piece it would call, and proof that the piece works.

**A confident wrong answer is the thing to fear, not an error message.** During
testing, four separate bugs were found that each produced a perfectly plausible
number. The worst one: when a restricted user asked about a song they were not allowed
to see, the math cheerfully returned "0.00%." Nothing looked broken. But 0% is a lie —
it says the song earned nothing, when the truth is that the user could not see it.
That is why the second set of hand-written books exists, and why every one of those
bugs is written down rather than quietly fixed.

## The One Thing to Remember

The safety does not come from telling the assistant to behave. It comes from locking
the data, so the assistant never has anything it should not show you in the first
place.

> For the full technical details, see the source documents.
