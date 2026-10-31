---
title: Contributing
sync: 2026-10-31
---

# Contributing

The project is MIT-licensed -- the license is the
whole of the legal arrangement; there is no CLA and no contributor
agreement beyond it. This page covers the practical half: how to get a
working build, what "done" means, and what a good change looks like.

## Getting to a working build

Follow [Installation](../user/installation.md) end to end first: a pinned
Julia 1.12.x, CMake with examples on, the scratch environment, and a
run of the quickstart. Everything on this page assumes that works before
you change anything. If it does not build before your change, you have
found a bug worth reporting before you write any code.

## Definition of done: the gates

A change to this repository is done when the gates say so, not when it
compiles. In increasing order of cost:

1. **Build clean.** CMake configure + build with no new warnings.
2. **Docs gates.** `.venv-docs/bin/mkdocs build --strict` and the parity
   script must pass with zero warnings -- every page exists in both
   locales, titles are translated, `sync` stamps agree, and no page leaks
   machine-specific strings. If you touch any page under `docs/`, run
   both.
3. **Acceptance gates.** The example gates of
   [acceptance gates](acceptance-gates.md), run by hand, sentinel lines
   green. Bridge or extraction changes owe the full set, not just the
   nearest example -- a past fix shipped a regression that only the
   layout-sensitivity gates caught.
4. **Rebuild artifacts if your change reaches them.** Julia-side package
   changes invalidate the sysimage and AOT builds
   ([rebuild from zero](rebuild.md)).

The gates are manual by design ([Known limitations](../user/known-limitations.md)).
That makes them your job.

## What a good change looks like

**Scoped small, committed in logical units.** The repository's history is
written as one commit per logical unit -- a feature, its tests, its
examples, its docs, its environment changes are separate commits, not one
landing. Keep that granularity; it is what makes bisects here actually
bisect.

**Fail loudly, never silently.** The house style is explicit errors with
a reason over quiet defaults: invalid handles carry a message readable
through `get_last_error_message()`, stale formats refuse to parse with a
regeneration hint, under-resolved runs assert instead of producing
plausible-looking wrong numbers. A contribution that adds a silent
fallback is working against the codebase.

**Match the documented contracts.** The public ABI is `bridge.h`; the
Fortran surface is `src/julia_binding.f90` and `src/julia_sdk.f90`; the
Julia side is the `FortranBridge` package. Extending any of them means
updating the layer above (and its docs page), not routing around it.

**Sanitize anything machine-specific.** Examples, scripts, and docs must
not hardcode local install paths, hostnames, or usernames -- use
placeholders, environment overrides, or exe-relative probing, as the
existing code does. The docs gates enforce this for prose; hold code and
comments to the same bar.

**Docs move with the code.** User-visible behavior changes update the
relevant page in *both* locales, with the `sync` stamp advanced. A PR
that changes what a gate checks updates [acceptance gates](acceptance-gates.md)
in the same commit series.

**Ground every claim.** Numbers in docs and comments come from the
validation runs, with provenance to the script that produced them; if you
change a number's source, change the number. An undocumented
measurement is a future person's wrong assumption.

## Pull requests

Open the PR against the primary branch (`master`) with:

- what the change does and why (a linked issue when there is one),
- which gates you ran and their sentinel output,
- for anything touching `src/bridge/`, why the GC/threading rules of
  [bridge internals](bridge-internals.md) still hold for your change.

Expect review to focus on the failure modes this project cares about:
error-path coverage, GC rooting of anything cached in a static, version
pinning, and honest docs. If a reviewer asks for a gate run you skipped,
that is the review working as intended -- see
[Lessons](lessons.md) for the receipts.

## Where to go next

- [Repository tour](repository-tour.md) -- where your change will live.
- [Bridge internals](bridge-internals.md) -- the rules reviewers will
  hold a bridge change against.
- [Further reading](further-reading.md) -- the upstream manuals behind
  the embedding and packaging machinery.
