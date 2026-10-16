# Contract Change — Adding, Reshaping, Removing a Published Field

Primarily about a proto contract: a message field or an RPC that has already been
published under an annotated tag. REST response fields share one of these rules and
differ on the rest — see the REST section at the bottom rather than assuming symmetry.

Contract rules are usually written down by whoever owns the contract — the contract's
own repo, or the team or organization behind it. Look where that owner keeps its
conventions: its `docs/`, or the entry file it gives AI tools (`CLAUDE.md`, `GEMINI.md`,
and the like). In a consumer repo, the contract repo is the one its pin names (`buf.gen.yaml`
`inputs.git_repo`); start from its rules (local clone or remote) and any team or
organization rules it points to, rather than treating the consumer's own files as the
contract's rules. Where the owner's rules speak, they govern; where none exist, say
so and apply the defaults here.

## Why proto is the hard case

A proto contract change is not atomic. Between the tag being pushed and each consumer
repointing, both shapes are live: consumers pin the contract in `buf.gen.yaml`
(`inputs.git_repo` + `tag:`) and their generated code is checked in, so a consumer that
has not repointed **still builds cleanly** against a field that no longer exists upstream.
No compiler error marks the breakage, and CI catches it only if the contract owner runs
`buf breaking`. Check the owner's CI config and contract rules before relying on it.

## Rules

**Purely additive changes need no consumer bump.** A new field, message, or RPC is safe:
a consumer whose pin predates the field parses it into unknown fields and passes it
through untouched. Ship it with whichever consumer change needs it.

**Reshaping an existing field is not additive.** Changing a scalar to `optional`,
narrowing a type, or changing units all break a pinned consumer, though by different
mechanisms — the attested one is `optional`: an intermediary that unmarshals and
remarshals against its own pinned schema (a gRPC forwarding proxy, for example) encodes an explicit `0` with the old non-optional schema,
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

**Removal and rename ship as their own change, after every consumer has moved off** —
never in the change that introduces the replacement. Removal also has one visible
artifact, and which one depends on a question this file cannot answer for you: read
the contract owner's field-numbering rules and decide which state applies. Before the
contract is declared stable, an owner may allow numbers to be reused freely with no
`reserved`. Once it is stable, a deleted or renamed field MUST carry `reserved` for both
the tag number and the field name. Compare those rules against the owner's tag list;
if they disagree about which state is in force, resolve it explicitly rather than
inferring. If the owner has no such rule, treat the contract as stable and reserve.

**Before removing, enumerate the consumers — do not wait for a build to fail.** `grep`
the identifier across every consumer repo and record the result in the change. An empty
result is the evidence; "nobody should be using it" is not. Unless the owner's CI runs
`buf breaking`, this grep is the only gate.

**Do not encode a special state as a sentinel value** (`-1` for "unknown", a magic
string) instead of making the field `optional`. **The exception to expect is
a translation-layer proto**, where `UNSPECIFIED` meaning "apply the downstream default"
is required by the downstream contract even though it looks like a sentinel. Do not
flag such a deviation without checking the downstream spec first, so on OAuth / SCIM /
RFC-shaped protos, read the spec before calling it a violation.

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
      carry `reserved` unless the owner's field-numbering rules say the pre-stable state applies
- [ ] A `grep` of the removed identifier across consumer repos is recorded, and empty
- [ ] No sentinel value encodes a special state, unless this is a translation-layer proto
      and the downstream spec requires it
