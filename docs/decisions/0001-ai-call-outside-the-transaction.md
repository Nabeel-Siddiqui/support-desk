# 1. The AI call and CRM/user lookups happen before the transaction, never inside it

## Status

Accepted (initial build).

## Context

Processing a ticket means three things have to happen: call an external
service (or a deterministic fallback) to analyze it, look it up against
a user/CRM lookup, and write all three resulting changes — analysis,
matching, triage — back onto the ticket row. The three writes clearly
belong in one transaction, so a crash mid-write can never leave a ticket
half-analyzed. The question was whether the *analysis itself* — a call
that can take seconds and can fail in ways entirely outside this app's
control — should happen inside that same transaction, or before it.

## Decision

`Pipeline.run_pipeline/1` calls `AI.analyze/1` and `Matcher.match/1`
first, as plain function calls with no transaction open. Only once both
results exist does an `Ecto.Multi` open, and that multi does nothing but
write already-computed values — three `Multi.update/3` calls, committed
atomically with `Repo.transaction/1`. No step inside the multi can block
on the network.

## Alternatives considered

- **Wrap the whole pipeline, AI call included, in one `Ecto.Multi` step.**
  Would guarantee the same atomicity with less code to read, but means a
  slow or hanging Claude API call holds a connection checked out from the
  pool for its entire duration. Under load, that's how one degraded
  external dependency exhausts the connection pool for every other
  request, including ones that have nothing to do with ticket
  processing.
- **Run the AI call in its own separate transaction, before the real
  one.** Avoids the long-held connection, but there's nothing to persist
  from the AI call alone — a transaction around a single read-only
  computation with no database write in it isn't doing anything a plain
  function call doesn't already do.

## Consequences

- A call to the AI step holds no database connection at all —
  `mark_processing/1` (see `Pipeline`'s moduledoc) is the one write that
  happens before analysis starts, specifically so the dashboard shows
  something other than "untouched" while that slow call is in flight,
  without holding a connection through it.
- The three-step `Multi` is fast and entirely local by the time it
  opens, so it holds its connection only as long as three `UPDATE`
  statements take — milliseconds, not however long an HTTP round trip to
  Claude takes.
- If the process dies between `mark_processing/1` and the final commit
  (OOM, node restart), the ticket is left showing `:processing`
  indefinitely. There's no retry queue in this app (see
  [ADR 2](0002-fire-and-forget-not-a-retry-queue.md)), so that's a
  visible, honest failure mode — a stale `:processing` row is a legible
  signal to whoever's looking at the dashboard, not a silent one.
