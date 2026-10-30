# SupportDesk — conventions

A support-ticket pipeline: a webhook receives a message, runs it through
analyze -> match -> triage, and saves the results back onto the same row.
Internal tool (HTTP Basic Auth, no per-user accounts). Portfolio-quality
Elixir/Phoenix app; hold every change to these rules. Keep it well-designed
and finished — add complexity only where this app actually needs it, not
speculatively.

## Architecture

- **Business logic lives in contexts** (`SupportDesk.Tickets`, ...).
  Contexts are the only modules that touch `Repo`.
- **The web layer (controllers, LiveViews) never calls `Repo` directly**
  and never builds `Ecto.Query`s itself — it calls context functions.
- Oban workers call context functions too; they don't reach into `Repo`
  directly. `ProcessTicketWorker` is a thin shell around
  `Tickets.process/1`.
- **The AI call and any external lookup happen before a database
  transaction opens, never inside one.** Holding a DB connection checked
  out from the pool across a slow network call is how one flaky external
  API takes down unrelated requests fighting over the same pool. See
  `SupportDesk.Tickets.Pipeline`'s moduledoc and
  [ADR 1](docs/decisions/0001-ai-call-outside-the-transaction.md).
- External services (the Claude API) are called directly from a context
  function with an explicit fallback path, not behind a `@behaviour` —
  this app has exactly one such call site, so the behaviour/Mox seam used
  elsewhere in this portfolio would be speculative here. The fallback
  itself (deterministic keyword matching) is what the test suite actually
  exercises. See [ADR 3](docs/decisions/0003-ai-fallback-is-the-default.md).

## Function contracts

- Every public context function has `@doc` and `@spec`.
- Functions that can fail return `{:ok, result}` or `{:error, reason}` —
  never raise for expected failure modes. Reserve `!`-suffixed functions
  for the conventional Phoenix "raise if truly not there" cases.
- No silently swallowed errors. A `rescue`/`catch` that discards the error
  without logging or returning it is a bug — `Pipeline.process/1`'s own
  `rescue` logs the exception and marks the ticket `:failed` rather than
  letting it vanish.

## Testing

- Every feature ships with tests alongside it in the same commit — not
  "add tests later."
- `AI_ENABLED` is never set in test config — every test runs the
  deterministic fallback, so the suite never needs `ANTHROPIC_API_KEY` and
  never makes a real network call.
- Prefer testing context functions directly over testing through the
  LiveView dashboard where the logic under test isn't actually about the
  UI.

## Style

- Run `mix format` before committing.
- `mix credo --strict` and `mix dialyzer` must be clean before a change is
  considered done.
