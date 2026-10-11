# Contract Change — Adding, Reshaping, Removing a Published Field

Primarily about `arx-platform-proto`: a message field or an RPC that has already been
published under an annotated tag. REST response fields share one of these rules and
differ on the rest — see the REST section at the bottom rather than assuming symmetry.

## Why proto is the hard case

A proto contract change is not atomic. Between the tag being pushed and each consumer
repointing, both shapes are live: consumers pin the contract in `buf.gen.yaml`
(`inputs.git_repo` + `tag:`) and their generated code is checked in, so a consumer that
has not repointed **still builds cleanly** against a field that no longer exists upstream.
No compiler error marks the breakage, and CI does not catch it either — `buf breaking` is
listed **Not enabled yet** in `arx-platform-proto/CLAUDE.md` §CI Enforcement Status,
"planned after v1 is tagged stable". Re-read that table before relying on this; it is
written to expire.

## Rules

**Purely additive changes need no consumer bump.** A new field, message, or RPC is safe:
a consumer whose pin predates the field parses it into unknown fields and passes it
through untouched. Ship it with whichever consumer change needs it.

**Reshaping an existing field is not additive.** Changing a scalar to `optional`,
narrowing a type, or changing units all break a pinned consumer, though by different
mechanisms — the attested one is `optional`: an intermediary that unmarshals and
remarshals against its own pinned schema (`arx-platform-core`'s `services.Forward`,
`internal/services/forward.go`) encodes an explicit `0` with the old non-optional schema,
drops it as a default, and the consumer downstream reads "not sent". A real zero becomes
permanently unreadable, silently.

The test is whether the field exists in a consumer's pin — **not** whether the consumer
reads it. To answer it, `grep` the workspace for `buf.gen.yaml`, read each `tag:`, and
resolve it:

| The consumer's pinned tag | Do |
|---|---|
| resolves, and contains the field | bump its pin in this same batch and regen, even with zero Go references |
| resolves, and predates the field | leave it alone — the field is in unknown fields |
| **does not resolve** | stop. That consumer is stranded on a deleted tag series, which is a separate cross-series upgrade to evaluate on its own. Do not fold it into this change |

The third row is the common one right now, not an edge case: the `v0.x` series was
deleted, and several consumers still pin tags from it.

**Removal and rename ship as their own change, after every consumer has moved off** —
never in the change that introduces the replacement. Removal also has one visible
artifact, and which one depends on a question this file cannot answer for you: read
`arx-platform-proto/CLAUDE.md` §Field Numbering and Reserved Declarations and decide
which of its two states applies. Pre-v1-stable, numbers may be reused freely with no
`reserved`. Once v1 is tagged stable, a deleted or renamed field MUST carry `reserved`
for both the tag number and the field name. That section's own prose and the repo's tag
list currently disagree about which state is in force, so resolve it explicitly rather
than inferring.

**Before removing, enumerate the consumers — do not wait for a build to fail.** `grep`
the identifier across every consumer repo and record the result in the change. An empty
result is the evidence; "nobody should be using it" is not. With `buf breaking` off,
this grep is the only gate.

**Do not encode a special state as a sentinel value** (`-1` for "unknown", a magic
string) instead of making the field `optional` — `arx-platform-proto/CLAUDE.md` forbids
it per AIP-163. **The exception is a translation-layer proto**, where `UNSPECIFIED`
meaning "apply the downstream default" is required by the downstream contract even
though it looks like a sentinel (§Translation Layer Exception). That section also says
not to flag an AIP-163 deviation without checking the downstream spec first, so on
OAuth / SCIM / RFC-shaped protos, read the spec before calling it a violation.

## REST response fields

The ordering rules carry over; the enforcement mechanism does not.

**Carries over:** additions are cheap, and a removal or rename is its own change. A
deployed client running an older build reads the response it was written against.

**Does not carry over:** there is no pin to bump and no consumer repo to grep — a browser
or an external client is not enumerable. The sanctioned removal path is versioning
instead: introduce `/api/vN+1` without the field rather than waiting for every consumer
to leave `/api/vN` (`references/rest-api.md` §Versioning). The zero-vs-absent hazard has
its own REST-side rule already: `references/rest-api.md` §Common Mistakes — never put
`omitempty` on a documented response field.

## Verification

- [ ] The change is purely additive, **or** every consumer whose pin resolves and already
      contains the field is bumped in the same batch
- [ ] Any consumer whose pin does not resolve is named and deferred, not silently bumped
- [ ] Removals ship separately from the change that introduced their replacement, and
      carry `reserved` if §Field Numbering says that state applies
- [ ] A `grep` of the removed identifier across consumer repos is recorded, and empty
- [ ] No sentinel value encodes a special state, unless this is a translation-layer proto
      and the downstream spec requires it
